package scripts

import (
	"fmt"
	"path/filepath"
	"strings"
)

// SourceKind identifies compile (.c) vs interpret (.py) source execution.
type SourceKind int

const (
	SourceKindNone SourceKind = iota
	SourceKindC
	SourceKindPy
)

// FirstToken returns the first whitespace-separated token of input.
func FirstToken(input string) string {
	fields := strings.Fields(strings.TrimSpace(input))
	if len(fields) == 0 {
		return ""
	}
	return fields[0]
}

// IsSQLScriptInput reports whether the first token names a SQL script (.sql).
func IsSQLScriptInput(input string) bool {
	token := FirstToken(input)
	return strings.HasSuffix(strings.ToLower(token), ".sql")
}

// SourceKindFromName returns the source kind for a filename or path.
func SourceKindFromName(name string) SourceKind {
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".c":
		return SourceKindC
	case ".py":
		return SourceKindPy
	default:
		return SourceKindNone
	}
}

// GetCSource loads a C source from os/ (embedded or filesystem) or an explicit path.
func GetCSource(name string) (string, error) {
	content, err := GetOSScript(name)
	if err != nil {
		return "", fmt.Errorf("failed to read C source %s", name)
	}
	return content, nil
}

// GetPySource loads a Python source from os/ (embedded or filesystem) or an explicit path.
func GetPySource(name string) (string, error) {
	content, err := GetOSScript(name)
	if err != nil {
		return "", fmt.Errorf("failed to read Python source %s", name)
	}
	return content, nil
}

// LoadScriptByName loads script content by filename extension (.sql or os/ including .c/.py).
func LoadScriptByName(name string) (string, error) {
	if strings.HasSuffix(strings.ToLower(name), ".sql") {
		return GetSQLScript(name)
	}
	return GetOSScript(name)
}
