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

// resolveVariablePromptInfos maps each &var to hint/default (Oracle sqlplus-like rules).
// Priority: ACCEPT > PROMPT banner containing &var > one PROMPT line per remaining variable
// (before first use; if multiple candidates, prefer line after prior vars' ACCEPT).
// Variables with no matching PROMPT keep empty Hint (standard "Enter value for &var:" input).
func resolveVariablePromptInfos(script string, variables []string) map[string]variablePromptInfo {
	result := make(map[string]variablePromptInfo, len(variables))
	if len(variables) == 0 {
		return result
	}

	lines := splitScriptLines(script)
	promptEntries := parsePromptEntries(lines)
	acceptByVar := parseAcceptByVariable(lines)
	acceptLines := acceptLineByVariable(lines)
	usedPrompt := make(map[int]bool)

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
		} else if banner, _, ok := bannerPromptLineIndex(lines, bareVariableName(variable)); ok {
			result[variable] = variablePromptInfo{Hint: banner}
		}
	}

	for varIdx, variable := range variables {
		bareUpper := strings.ToUpper(bareVariableName(variable))
		if _, ok := acceptByVar[bareUpper]; ok {
			continue
		}
		if isBannerPromptLine(lines, bareVariableName(variable)) {
			continue
		}

		idx := firstIdx[variable]
		candidates := candidatePromptsBeforeVar(promptEntries, usedPrompt, idx)
		if pe, ok := pickPromptForOpenVar(candidates, maxPriorAcceptLine(variables, varIdx, acceptLines)); ok {
			result[variable] = variablePromptInfo{Hint: pe.text}
			usedPrompt[pe.line] = true
		}
		// No dedicated PROMPT: leave Hint empty → executor shows "Enter value for &var:"
	}

	return result
}

func firstVariableLineIndex(lines []string, bare string) int {
	patterns := []string{
		regexp.QuoteMeta("&&" + bare) + `\b`,
		regexp.QuoteMeta("&" + bare) + `\b`,
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
