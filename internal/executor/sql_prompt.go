package executor

// SQL*Plus client command parsing: PROMPT/ACCEPT hints and stripping for non-Oracle CLIs.

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/yihan/ytop/internal/utils"
)

// variablePromptInfo holds client-side hint and default for a substitution variable.
type variablePromptInfo struct {
	Hint    string
	Default string
}

var (
	acceptLineRe          = regexp.MustCompile(`(?i)^\s*ACCEPT\s+(\w+)\b`)
	acceptPromptRe        = regexp.MustCompile(`(?i)\bprompt\s+'([^']*)'`)
	acceptDefaultQuotedRe = regexp.MustCompile(`(?i)\bdefault\s+'([^']*)'`)
	acceptDefaultBareRe   = regexp.MustCompile(`(?i)\bdefault\s+(\S+)`)
	scriptVariableRe      = regexp.MustCompile(`(&&?)(\w+)\b`)
)

// bareVariableName strips leading & from &var or &&var.
func bareVariableName(variable string) string {
	return strings.TrimLeft(variable, "&")
}

// parseSQLPlusPromptLine extracts display text from a PROMPT or PRO line at line start.
func parseSQLPlusPromptLine(line string) (text string, ok bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return "", false
	}
	upper := strings.ToUpper(trimmed)
	if upper == "PROMPT" {
		return "", true
	}
	if strings.HasPrefix(upper, "PROMPT ") {
		return strings.TrimSpace(trimmed[len("PROMPT"):]), true
	}
	if strings.HasPrefix(upper, "PRO ") {
		return strings.TrimSpace(trimmed[len("PRO"):]), true
	}
	return "", false
}

// parseAcceptLine parses SQL*Plus ACCEPT var PROMPT '...' [default ...].
func parseAcceptLine(line string) (varName, hint, defaultVal string, ok bool) {
	trimmed := strings.TrimSpace(line)
	if !acceptLineRe.MatchString(trimmed) {
		return "", "", "", false
	}
	m := acceptLineRe.FindStringSubmatch(trimmed)
	if len(m) < 2 {
		return "", "", "", false
	}
	varName = m[1]
	if pm := acceptPromptRe.FindStringSubmatch(trimmed); len(pm) > 1 {
		hint = pm[1]
	}
	if dm := acceptDefaultQuotedRe.FindStringSubmatch(trimmed); len(dm) > 1 {
		defaultVal = dm[1]
	} else if dm := acceptDefaultBareRe.FindStringSubmatch(trimmed); len(dm) > 1 {
		defaultVal = dm[1]
	}
	return varName, hint, defaultVal, true
}

func parseAcceptByVariable(lines []string) map[string]variablePromptInfo {
	out := make(map[string]variablePromptInfo)
	for _, line := range lines {
		if vn, hint, def, ok := parseAcceptLine(line); ok {
			out[strings.ToUpper(vn)] = variablePromptInfo{Hint: hint, Default: def}
		}
	}
	return out
}

// promptEntry is one non-empty PROMPT/PRO line with its script line index.
type promptEntry struct {
	line int
	text string
}

func parsePromptEntries(lines []string) []promptEntry {
	var entries []promptEntry
	for i, line := range lines {
		if text, ok := parseSQLPlusPromptLine(line); ok && text != "" {
			entries = append(entries, promptEntry{line: i, text: text})
		}
	}
	return entries
}

func acceptLineByVariable(lines []string) map[string]int {
	out := make(map[string]int)
	for i, line := range lines {
		if vn, _, _, ok := parseAcceptLine(line); ok {
			out[strings.ToUpper(vn)] = i
		}
	}
	return out
}

func maxPriorAcceptLine(variables []string, varIndex int, acceptLines map[string]int) int {
	maxLine := -1
	for i := 0; i < varIndex; i++ {
		bare := strings.ToUpper(bareVariableName(variables[i]))
		if line, ok := acceptLines[bare]; ok && line > maxLine {
			maxLine = line
		}
	}
	return maxLine
}

func bannerPromptLineIndex(lines []string, bare string) (text string, line int, ok bool) {
	needle := strings.ToUpper("&" + bare)
	for i, line := range lines {
		if text, ok := parseSQLPlusPromptLine(line); ok && text != "" {
			if strings.Contains(strings.ToUpper(text), needle) {
				return text, i, true
			}
		}
	}
	return "", -1, false
}

func candidatePromptsBeforeVar(
	entries []promptEntry,
	used map[int]bool,
	endLine int,
) []promptEntry {
	if endLine < 0 {
		return nil
	}
	var out []promptEntry
	for _, pe := range entries {
		if used[pe.line] {
			continue
		}
		if pe.line < endLine {
			out = append(out, pe)
		}
	}
	return out
}

func pickPromptForOpenVar(
	candidates []promptEntry,
	afterAcceptLine int,
) (promptEntry, bool) {
	if len(candidates) == 0 {
		return promptEntry{}, false
	}
	if len(candidates) == 1 {
		return candidates[0], true
	}
	if afterAcceptLine >= 0 {
		for _, pe := range candidates {
			if pe.line > afterAcceptLine {
				return pe, true
			}
		}
	}
	return candidates[0], true
}

func isBannerPromptLine(lines []string, bare string) bool {
	_, _, ok := bannerPromptLineIndex(lines, bare)
	return ok
}

// isPromptOrProLine reports whether line is a SQL*Plus PROMPT/PRO client command.
func isPromptOrProLine(line string) bool {
	_, ok := parseSQLPlusPromptLine(line)
	return ok
}

// promptBlockLine is one logical line inside a contiguous PROMPT/PRO block.
type promptBlockLine struct {
	lineIndex int
	text      string
	blank     bool
}

// collectPromptBlocksInRange returns contiguous PROMPT/PRO blocks in [startLine, endLine).
func collectPromptBlocksInRange(lines []string, startLine, endLine int) [][]promptBlockLine {
	if startLine < 0 {
		startLine = 0
	}
	if endLine < 0 || endLine > len(lines) {
		endLine = len(lines)
	}
	if startLine >= endLine {
		return nil
	}

	var blocks [][]promptBlockLine
	var current []promptBlockLine

	flush := func() {
		if len(current) == 0 {
			return
		}
		block := make([]promptBlockLine, len(current))
		copy(block, current)
		blocks = append(blocks, block)
		current = current[:0]
	}

	for i := startLine; i < endLine; i++ {
		line := lines[i]
		if !isPromptOrProLine(line) {
			flush()
			continue
		}
		text, _ := parseSQLPlusPromptLine(line)
		trimmed := strings.TrimSpace(line)
		upper := strings.ToUpper(trimmed)
		if upper == "PROMPT" {
			current = append(current, promptBlockLine{lineIndex: i, blank: true})
		} else {
			current = append(current, promptBlockLine{lineIndex: i, text: text})
		}
	}
	flush()
	return blocks
}

// formatYashanDBPromptBlocks formats PROMPT/PRO blocks in [startLine, endLine) for terminal display.
// Displayed line indices are recorded in displayed (if non-nil).
func formatYashanDBPromptBlocks(script string, startLine, endLine int, displayed map[int]bool) string {
	lines := splitScriptLines(script)
	blocks := collectPromptBlocksInRange(lines, startLine, endLine)
	if len(blocks) == 0 {
		return ""
	}

	var out strings.Builder
	for bi, block := range blocks {
		if bi > 0 {
			out.WriteByte('\n')
		}
		for _, pl := range block {
			if displayed != nil && displayed[pl.lineIndex] {
				continue
			}
			if displayed != nil {
				displayed[pl.lineIndex] = true
			}
			if pl.blank {
				out.WriteByte('\n')
			} else {
				out.WriteString(pl.text)
				out.WriteByte('\n')
			}
		}
	}
	return strings.TrimRight(out.String(), "\n")
}

// printYashanDBPromptBlocks prints PROMPT/PRO blocks in [startLine, endLine).
func printYashanDBPromptBlocks(script string, startLine, endLine int, displayed map[int]bool) {
	text := formatYashanDBPromptBlocks(script, startLine, endLine, displayed)
	if text == "" {
		return
	}
	fmt.Println()
	fmt.Println(text)
}

// variablePromptOrder holds resolved interaction order and optional prelude metadata.
type variablePromptOrder struct {
	Ordered        []string
	Source         string // "accept", "prelude", or "sql"
	PreludeHints   map[string]string
	PreludeLineIdx map[string]int
}

// resolveVariablePromptOrder picks substitution variable interaction order.
// Priority: ACCEPT file order (+ remaining SQL order) > PROMPT prelude name match > SQL first-use.
func resolveVariablePromptOrder(script string) variablePromptOrder {
	sqlOrder := collectScriptVariables(script)
	out := variablePromptOrder{
		Ordered:        sqlOrder,
		Source:         "sql",
		PreludeHints:   map[string]string{},
		PreludeLineIdx: map[string]int{},
	}
	if len(sqlOrder) == 0 {
		return out
	}

	lines := splitScriptLines(script)
	tokenByBare := make(map[string]string, len(sqlOrder))
	for _, v := range sqlOrder {
		tokenByBare[strings.ToUpper(bareVariableName(v))] = v
	}

	acceptNames := parseAcceptOrderNames(lines)
	if len(acceptNames) > 0 {
		out.Ordered = orderByAcceptNames(acceptNames, sqlOrder, tokenByBare)
		out.Source = "accept"
		return out
	}

	firstVarLine := firstAnyVariableLineIndex(lines, sqlOrder)
	if ordered, hints, lineIdx, ok := matchPreludePromptOrder(lines, firstVarLine, sqlOrder); ok {
		out.Ordered = ordered
		out.Source = "prelude"
		out.PreludeHints = hints
		out.PreludeLineIdx = lineIdx
	}
	return out
}

func parseAcceptOrderNames(lines []string) []string {
	var names []string
	seen := make(map[string]bool)
	for _, line := range lines {
		if vn, _, _, ok := parseAcceptLine(line); ok {
			upper := strings.ToUpper(vn)
			if !seen[upper] {
				names = append(names, upper)
				seen[upper] = true
			}
		}
	}
	return names
}

func orderByAcceptNames(acceptNames []string, sqlOrder []string, tokenByBare map[string]string) []string {
	ordered := make([]string, 0, len(sqlOrder))
	seen := make(map[string]bool)
	for _, bareUpper := range acceptNames {
		if tok, ok := tokenByBare[bareUpper]; ok && !seen[tok] {
			ordered = append(ordered, tok)
			seen[tok] = true
		}
	}
	for _, v := range sqlOrder {
		if !seen[v] {
			ordered = append(ordered, v)
			seen[v] = true
		}
	}
	return ordered
}

func firstAnyVariableLineIndex(lines []string, variables []string) int {
	first := -1
	for _, variable := range variables {
		idx := firstVariableLineIndex(lines, bareVariableName(variable))
		if idx < 0 {
			continue
		}
		if first < 0 || idx < first {
			first = idx
		}
	}
	return first
}

func preludePromptEntriesBeforeLine(lines []string, endLine int) []promptEntry {
	if endLine < 0 {
		endLine = len(lines)
	}
	blocks := collectPromptBlocksInRange(lines, 0, endLine)
	var entries []promptEntry
	for _, block := range blocks {
		for _, pl := range block {
			if pl.blank || pl.text == "" {
				continue
			}
			entries = append(entries, promptEntry{line: pl.lineIndex, text: pl.text})
		}
	}
	return entries
}

func matchVariableNameInPromptText(text, bare string) bool {
	if bare == "" {
		return false
	}
	for _, pat := range variablePromptPatterns(bare) {
		if matched, _ := regexp.MatchString(pat, text); matched {
			return true
		}
	}
	return false
}

// variablePromptPatterns returns regexes that link a substitution variable to PROMPT text.
// Includes common YashanDB script wording (e.g. "table name" for &&tablename).
func variablePromptPatterns(bare string) []string {
	pats := []string{`(?i)\b` + regexp.QuoteMeta(bare) + `\b`}
	switch strings.ToLower(bare) {
	case "tablename":
		pats = append(pats, `(?i)\btable\b`)
	case "partname":
		pats = append(pats, `(?i)\bpartition\b`)
	case "colname":
		pats = append(pats, `(?i)\bcolumn\b`)
	}
	return pats
}

func matchPreludePromptOrder(lines []string, firstVarLine int, sqlOrder []string) ([]string, map[string]string, map[string]int, bool) {
	prelude := preludePromptEntriesBeforeLine(lines, firstVarLine)
	if len(prelude) != len(sqlOrder) {
		return nil, nil, nil, false
	}

	ordered := make([]string, 0, len(sqlOrder))
	hints := make(map[string]string, len(sqlOrder))
	lineIdx := make(map[string]int, len(sqlOrder))
	used := make(map[string]bool)

	for _, pe := range prelude {
		found := ""
		for _, v := range sortVariablesByBareNameLen(sqlOrder) {
			if used[v] {
				continue
			}
			bare := bareVariableName(v)
			if matchVariableNameInPromptText(pe.text, bare) {
				found = v
				break
			}
		}
		if found == "" {
			return nil, nil, nil, false
		}
		ordered = append(ordered, found)
		hints[found] = pe.text
		lineIdx[found] = pe.line
		used[found] = true
	}
	if len(ordered) != len(sqlOrder) {
		return nil, nil, nil, false
	}
	return ordered, hints, lineIdx, true
}

func sortVariablesByBareNameLen(variables []string) []string {
	out := append([]string(nil), variables...)
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			li, lj := len(bareVariableName(out[i])), len(bareVariableName(out[j]))
			if lj > li || (lj == li && out[j] < out[i]) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

// yashanDBPromptWindow returns the half-open line range for PROMPT blocks shown before variables[i].
func yashanDBPromptWindow(variables []string, varIndex int, lines []string, preludeLineByVar map[string]int) (start, end int) {
	if varIndex < 0 || varIndex >= len(variables) {
		return 0, 0
	}
	if preludeLineByVar != nil {
		if line, ok := preludeLineByVar[variables[varIndex]]; ok {
			return line, line + 1
		}
	}
	end = firstVariableLineIndex(lines, bareVariableName(variables[varIndex]))
	if varIndex == 0 {
		return 0, end
	}
	prev := firstVariableLineIndex(lines, bareVariableName(variables[varIndex-1]))
	if prev < 0 {
		return 0, end
	}
	return prev + 1, end
}

// resolveVariablePromptInfos maps each &var to hint/default (Oracle sqlplus-like rules).
// Priority: ACCEPT > preludeHints > PROMPT banner containing &var > one PROMPT line per remaining variable.
// displayedPromptLines marks PROMPT lines already shown via printYashanDBPromptBlocks (yashandb).
func resolveVariablePromptInfos(script string, variables []string, displayedPromptLines map[int]bool, preludeHints map[string]string) map[string]variablePromptInfo {
	result := make(map[string]variablePromptInfo, len(variables))
	if len(variables) == 0 {
		return result
	}

	lines := splitScriptLines(script)
	promptEntries := parsePromptEntries(lines)
	acceptByVar := parseAcceptByVariable(lines)
	acceptLines := acceptLineByVariable(lines)
	usedPrompt := make(map[int]bool)
	for line := range displayedPromptLines {
		usedPrompt[line] = true
	}

	firstIdx := make(map[string]int, len(variables))
	for _, variable := range variables {
		firstIdx[variable] = firstVariableLineIndex(lines, bareVariableName(variable))
	}

	// Mark banner PROMPT lines (bound via &var in text).
	for _, variable := range variables {
		if _, bLine, ok := bannerPromptLineIndex(lines, bareVariableName(variable)); ok {
			usedPrompt[bLine] = true
		}
	}

	for _, variable := range variables {
		bareUpper := strings.ToUpper(bareVariableName(variable))
		if info, ok := acceptByVar[bareUpper]; ok {
			result[variable] = info
		} else if hint, ok := preludeHints[variable]; ok && hint != "" {
			result[variable] = variablePromptInfo{Hint: hint}
		} else if banner, _, ok := bannerPromptLineIndex(lines, bareVariableName(variable)); ok {
			result[variable] = variablePromptInfo{Hint: banner}
		}
	}

	for varIdx, variable := range variables {
		bareUpper := strings.ToUpper(bareVariableName(variable))
		if _, ok := acceptByVar[bareUpper]; ok {
			continue
		}
		if _, ok := preludeHints[variable]; ok {
			continue
		}
		if isBannerPromptLine(lines, bareVariableName(variable)) {
			continue
		}
		if info, ok := result[variable]; ok && info.Hint != "" {
			continue
		}

		idx := firstIdx[variable]
		candidates := candidatePromptsBeforeVar(promptEntries, usedPrompt, idx)
		if pe, ok := pickPromptForOpenVar(candidates, maxPriorAcceptLine(variables, varIdx, acceptLines)); ok {
			result[variable] = variablePromptInfo{Hint: pe.text}
			usedPrompt[pe.line] = true
		}
	}

	return result
}

func firstVariableLineIndex(lines []string, bare string) int {
	patterns := []string{
		regexp.QuoteMeta("&&"+bare) + `\b`,
		regexp.QuoteMeta("&"+bare) + `\b`,
	}
	for i, line := range lines {
		if isSQLCommentLine(line) {
			continue
		}
		upper := strings.ToUpper(line)
		bareUpper := strings.ToUpper(bare)
		if strings.Contains(upper, "&&"+bareUpper) || strings.Contains(upper, "&"+bareUpper) {
			for _, pat := range patterns {
				if matched, _ := regexp.MatchString(`(?i)`+pat, line); matched {
					return i
				}
			}
		}
	}
	return -1
}

// isSQLCommentLine reports line-start SQL*Plus/sql comment (not code after --).
func isSQLCommentLine(line string) bool {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return false
	}
	if strings.HasPrefix(trimmed, "--") {
		return true
	}
	return strings.HasPrefix(strings.ToUpper(trimmed), "REM ")
}

func splitScriptLines(script string) []string {
	script = strings.ReplaceAll(script, "\r\n", "\n")
	script = strings.ReplaceAll(script, "\r", "\n")
	return strings.Split(script, "\n")
}

// collectScriptVariables finds &var and &&var in script order (skips -- / REM comment lines).
func collectScriptVariables(script string) []string {
	seen := make(map[string]struct {
		name     string
		isDouble bool
	})
	var variables []string

	for _, line := range splitScriptLines(script) {
		if isSQLCommentLine(line) {
			continue
		}
		for _, match := range scriptVariableRe.FindAllStringSubmatch(line, -1) {
			if len(match) <= 2 {
				continue
			}
			prefix := match[1]
			varName := match[2]
			isDouble := prefix == "&&"
			key := prefix + varName

			if existing, exists := seen[varName]; exists {
				if existing.isDouble != isDouble {
					if !utils.Contains(variables, key) {
						variables = append(variables, key)
					}
				}
			} else {
				seen[varName] = struct {
					name     string
					isDouble bool
				}{varName, isDouble}
				variables = append(variables, key)
			}
		}
	}

	return variables
}

// stripSQLPlusClientCommands removes PROMPT/PRO/ACCEPT lines unsupported outside sqlplus.
func stripSQLPlusClientCommands(script string) string {
	lines := splitScriptLines(script)
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		upper := strings.ToUpper(trimmed)
		if upper == "PROMPT" || strings.HasPrefix(upper, "PROMPT ") || strings.HasPrefix(upper, "PRO ") {
			continue
		}
		if acceptLineRe.MatchString(trimmed) {
			continue
		}
		if strings.HasPrefix(upper, "REM PROMPT") {
			continue
		}
		out = append(out, line)
	}
	return strings.Join(out, "\n")
}

func formatVariableInputPrompt(variable, defaultVal string) string {
	if defaultVal != "" {
		return fmt.Sprintf("\r\nEnter value for %s (default %s): ", variable, defaultVal)
	}
	return fmt.Sprintf("\r\nEnter value for %s: ", variable)
}

func printVariableHint(hint string) {
	if hint == "" {
		return
	}
	fmt.Println()
	fmt.Println(hint)
}
