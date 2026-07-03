package scripts

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

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
