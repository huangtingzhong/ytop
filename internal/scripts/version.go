// Package scripts 内版本号解析与比较，供脚本版本匹配使用。
package scripts

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

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
