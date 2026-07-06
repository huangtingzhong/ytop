package scripts

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Package scripts 内版本号解析与比较，供脚本版本匹配使用。

var versionTokenRe = regexp.MustCompile(`(\d+(?:\.\d+)*)`)

// ParseVersion parses dotted numeric version strings such as "23.5.1".
func ParseVersion(s string) ([]int, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, fmt.Errorf("empty version")
	}
	parts := strings.Split(s, ".")
	out := make([]int, 0, len(parts))
	for _, p := range parts {
		if p == "" {
			return nil, fmt.Errorf("invalid version %q", s)
		}
		n, err := strconv.Atoi(p)
		if err != nil {
			return nil, fmt.Errorf("invalid version %q", s)
		}
		out = append(out, n)
	}
	return out, nil
}

// CompareVersions compares two dotted versions. Returns -1/0/1.
func CompareVersions(a, b string) (int, error) {
	av, err := ParseVersion(a)
	if err != nil {
		return 0, err
	}
	bv, err := ParseVersion(b)
	if err != nil {
		return 0, err
	}
	max := len(av)
	if len(bv) > max {
		max = len(bv)
	}
	for i := 0; i < max; i++ {
		var ai, bi int
		if i < len(av) {
			ai = av[i]
		}
		if i < len(bv) {
			bi = bv[i]
		}
		if ai < bi {
			return -1, nil
		}
		if ai > bi {
			return 1, nil
		}
	}
	return 0, nil
}

// VersionMatchesPrefix reports whether dbVersion matches a prefix such as "23.5".
func VersionMatchesPrefix(dbVersion, prefix string) bool {
	if strings.TrimSpace(prefix) == "" {
		return true
	}
	if dbVersion == prefix {
		return true
	}
	return strings.HasPrefix(dbVersion, prefix+".")
}

// ExtractVersionFromText finds the first dotted version token in CLI output.
func ExtractVersionFromText(text string) string {
	m := versionTokenRe.FindStringSubmatch(text)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

// looksLikeVersion reports whether s is a dotted numeric version suffix.
func looksLikeVersion(s string) bool {
	if s == "" {
		return false
	}
	_, err := ParseVersion(s)
	return err == nil
}

type versionConstraint struct {
	isRange bool
	low     string
	high    string
}

func parseSupportedSpec(spec string) []versionConstraint {
	spec = strings.TrimSpace(spec)
	if spec == "" {
		return nil
	}
	var out []versionConstraint
	for _, token := range strings.Split(spec, ",") {
		token = strings.TrimSpace(token)
		if token == "" {
			continue
		}
		if c, ok := parseVersionConstraintToken(token); ok {
			out = append(out, c)
		}
	}
	return out
}

func parseVersionConstraintToken(token string) (versionConstraint, bool) {
	if idx := strings.Index(token, "-"); idx > 0 {
		low := strings.TrimSpace(token[:idx])
		high := strings.TrimSpace(token[idx+1:])
		if looksLikeVersion(low) && looksLikeVersion(high) {
			return versionConstraint{isRange: true, low: low, high: high}, true
		}
	}
	if looksLikeVersion(token) {
		return versionConstraint{low: token}, true
	}
	return versionConstraint{}, false
}

func (c versionConstraint) matches(dbVersion string) bool {
	if c.isRange {
		if cmp, err := CompareVersions(dbVersion, c.low); err != nil || cmp < 0 {
			return false
		}
		if cmp, err := CompareVersions(dbVersion, c.high); err != nil || cmp > 0 {
			return false
		}
		return true
	}
	return VersionMatchesPrefix(dbVersion, c.low)
}

func (c versionConstraint) score(dbVersion string) int {
	if !c.matches(dbVersion) {
		return 0
	}
	if c.isRange {
		width := len(strings.Split(c.high, ".")) - len(strings.Split(c.low, "."))
		if width < 0 {
			width = 0
		}
		return 150 + len(strings.Split(c.low, "."))*10 + width*5 + len(c.low) + len(c.high)
	}
	if dbVersion == c.low {
		return 300 + len(strings.Split(c.low, "."))*20
	}
	return 200 + len(strings.Split(c.low, "."))*10 + len(c.low)
}

func constraintsMatch(constraints []versionConstraint, dbVersion string) bool {
	if len(constraints) == 0 {
		return false
	}
	for _, c := range constraints {
		if c.matches(dbVersion) {
			return true
		}
	}
	return false
}

func bestConstraintScore(constraints []versionConstraint, dbVersion string) int {
	best := 0
	for _, c := range constraints {
		if s := c.score(dbVersion); s > best {
			best = s
		}
	}
	return best
}

// CurrentDBVersion is the active database version for script resolution.
// Set from --db-version or auto-detected via DB CLI -v.
var CurrentDBVersion string

// LastResolvedScript records the physical script chosen for the most recent lookup.
var LastResolvedScript string

type scriptVersionMeta struct {
	FileName     string
	LogicalName  string
	SuffixVer    string
	SupportedRaw string
	Constraints  []versionConstraint
}

type scriptCandidate struct {
	meta    scriptVersionMeta
	content []byte
}

// ResolveSQLScriptName picks the best physical SQL script for a logical name and DB version.
func ResolveSQLScriptName(logicalName, dbVersion string) (string, error) {
	logicalName = strings.TrimSpace(logicalName)
	dbVersion = strings.TrimSpace(dbVersion)
	if logicalName == "" {
		return "", fmt.Errorf("empty script name")
	}
	if dbVersion == "" {
		return logicalName, nil
	}
	if hasVersionSuffix(logicalName) {
		return logicalName, nil
	}

	base := strings.TrimSuffix(logicalName, filepath.Ext(logicalName))
	candidates, err := listSQLScriptCandidates(base)
	if err != nil {
		return logicalName, err
	}
	if len(candidates) == 0 {
		return logicalName, nil
	}

	var matched []scoredCandidate
	for _, c := range candidates {
		if !scriptMatchesVersion(c.meta, dbVersion) {
			continue
		}
		matched = append(matched, scoredCandidate{
			filename: c.meta.FileName,
			score:    scoreScriptMatch(c.meta, dbVersion),
		})
	}
	if len(matched) == 0 {
		return logicalName, fmt.Errorf("no script variant of %q matches DB version %q", logicalName, dbVersion)
	}

	sort.Slice(matched, func(i, j int) bool {
		if matched[i].score != matched[j].score {
			return matched[i].score > matched[j].score
		}
		return matched[i].filename < matched[j].filename
	})
	return matched[0].filename, nil
}

type scoredCandidate struct {
	filename string
	score    int
}

func hasVersionSuffix(filename string) bool {
	_, ver := parseScriptFilename(filename)
	return ver != ""
}

func parseScriptFilename(filename string) (logicalBase, suffixVersion string) {
	ext := filepath.Ext(filename)
	name := strings.TrimSuffix(filename, ext)
	idx := strings.LastIndex(name, "_")
	if idx <= 0 {
		return name, ""
	}
	suffix := name[idx+1:]
	if !looksLikeVersion(suffix) {
		return name, ""
	}
	return name[:idx], suffix
}

func parseScriptVersionMeta(filename string, content []byte) scriptVersionMeta {
	base, suffix := parseScriptFilename(filename)
	fields := parseScriptHeaderFields(content)
	logical := fields.FileName
	if logical == "" {
		logical = base + filepath.Ext(filename)
	}
	meta := scriptVersionMeta{
		FileName:    filename,
		LogicalName: logical,
		SuffixVer:   suffix,
	}
	if fields.Supported != "" {
		meta.SupportedRaw = strings.TrimSpace(fields.Supported)
		meta.Constraints = parseSupportedSpec(meta.SupportedRaw)
	}
	return meta
}

func scriptMatchesVersion(meta scriptVersionMeta, dbVersion string) bool {
	if len(meta.Constraints) > 0 {
		return constraintsMatch(meta.Constraints, dbVersion)
	}

	if meta.SuffixVer != "" {
		return VersionMatchesPrefix(dbVersion, meta.SuffixVer)
	}

	// Generic fallback script without version metadata applies to all versions.
	return true
}

func scoreScriptMatch(meta scriptVersionMeta, dbVersion string) int {
	score := 0
	if len(meta.Constraints) > 0 {
		score += 1000 + bestConstraintScore(meta.Constraints, dbVersion)
	}
	if meta.SuffixVer != "" {
		score += 800 + len(strings.Split(meta.SuffixVer, "."))*20 + len(meta.SuffixVer)
	}
	if meta.SuffixVer == "" && len(meta.Constraints) == 0 {
		score = 1
	}
	return score
}

func listSQLScriptCandidates(logicalBase string) ([]scriptCandidate, error) {
	seen := make(map[string]struct{})
	var out []scriptCandidate

	add := func(filename string, content []byte) {
		base, _ := parseScriptFilename(filename)
		if base != logicalBase {
			return
		}
		if _, ok := seen[filename]; ok {
			return
		}
		seen[filename] = struct{}{}
		out = append(out, scriptCandidate{
			meta:    parseScriptVersionMeta(filename, content),
			content: content,
		})
	}

	if scriptsDir, err := getScriptDir(); err == nil && scriptsDir != "" {
		dir := filepath.Join(scriptsDir, "sql", CurrentDBType)
		entries, err := os.ReadDir(dir)
		if err == nil {
			for _, entry := range entries {
				if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".sql") {
					continue
				}
				content, err := os.ReadFile(filepath.Join(dir, entry.Name()))
				if err != nil {
					continue
				}
				add(entry.Name(), content)
			}
		}
	}

	_ = fs.WalkDir(defaultEmbeddedFS, "sql/"+CurrentDBType, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(d.Name(), ".sql") {
			return nil
		}
		content, err := fs.ReadFile(defaultEmbeddedFS, path)
		if err != nil {
			return nil
		}
		add(d.Name(), content)
		return nil
	})

	if ExternalEmbeddedFS != nil {
		base := filepath.Join("scripts", "sql", CurrentDBType)
		_ = fs.WalkDir(ExternalEmbeddedFS, base, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(d.Name(), ".sql") {
				return nil
			}
			content, err := fs.ReadFile(ExternalEmbeddedFS, path)
			if err != nil {
				return nil
			}
			add(d.Name(), content)
			return nil
		})
	}

	return out, nil
}

func sqlScriptExists(name string) bool {
	if isExplicitPath(name) {
		if _, err := os.Stat(name); err == nil {
			return true
		}
	}
	_, err := readSQLScriptBytes(name)
	return err == nil
}

func readSQLScriptBytes(name string) ([]byte, error) {
	if scriptsDir, err := getScriptDir(); err == nil && scriptsDir != "" {
		path := filepath.Join(scriptsDir, "sql", CurrentDBType, name)
		if content, err := os.ReadFile(path); err == nil {
			return content, nil
		}
	}
	path := "sql/" + CurrentDBType + "/" + name
	if content, err := fs.ReadFile(defaultEmbeddedFS, path); err == nil {
		return content, nil
	}
	if ExternalEmbeddedFS != nil {
		path = filepath.Join("scripts", "sql", CurrentDBType, name)
		if content, err := fs.ReadFile(ExternalEmbeddedFS, path); err == nil {
			return content, nil
		}
	}
	return nil, fmt.Errorf("script not found: %s", name)
}
