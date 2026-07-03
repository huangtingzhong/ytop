package scripts

import (
	"strings"
)

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
		return 150 + len(strings.Split(c.low, "."))*10 + width*5 + len(c.low)+len(c.high)
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
