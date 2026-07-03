package scripts

import "testing"

func TestParseVersionAndCompare(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"23.5.1", "23.5", 1},
		{"23.5", "23.5.1", -1},
		{"23.5", "23.5", 0},
		{"24.0", "23.99", 1},
	}
	for _, tc := range cases {
		got, err := CompareVersions(tc.a, tc.b)
		if err != nil {
			t.Fatalf("CompareVersions(%q, %q): %v", tc.a, tc.b, err)
		}
		if got != tc.want {
			t.Fatalf("CompareVersions(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
}

func TestVersionMatchesPrefix(t *testing.T) {
	if !VersionMatchesPrefix("23.5.1", "23.5") {
		t.Fatal("expected prefix match")
	}
	if VersionMatchesPrefix("23.4.1", "23.5") {
		t.Fatal("expected no prefix match")
	}
}

func TestExtractVersionFromText(t *testing.T) {
	got := ExtractVersionFromText("YashanDB Release 23.5.1.104 Client")
	if got != "23.5.1.104" {
		t.Fatalf("ExtractVersionFromText = %q, want 23.5.1.104", got)
	}
}

func TestParseScriptFilename(t *testing.T) {
	base, ver := parseScriptFilename("we_23.5.sql")
	if base != "we" || ver != "23.5" {
		t.Fatalf("parseScriptFilename(we_23.5.sql) = (%q, %q)", base, ver)
	}
	base, ver = parseScriptFilename("log_switch_size.sql")
	if base != "log_switch_size" || ver != "" {
		t.Fatalf("parseScriptFilename(log_switch_size.sql) = (%q, %q)", base, ver)
	}
}

func TestParseSupportedSpec(t *testing.T) {
	constraints := parseSupportedSpec("23.4,23.5-24.0,25.0")
	if len(constraints) != 3 {
		t.Fatalf("parseSupportedSpec len = %d, want 3", len(constraints))
	}
	if !constraints[0].matches("23.4.1") {
		t.Fatal("expected 23.4.1 to match 23.4")
	}
	if !constraints[1].matches("23.6.0") {
		t.Fatal("expected 23.6.0 to match 23.5-24.0")
	}
	if constraints[1].matches("24.1.0") {
		t.Fatal("expected 24.1.0 to miss 23.5-24.0")
	}
	if !constraints[2].matches("25.0.1") {
		t.Fatal("expected 25.0.1 to match 25.0")
	}
}

func TestResolveSQLScriptName(t *testing.T) {
	CurrentDBType = "yashandb"
	CurrentDBVersion = "23.5.1"

	got, err := ResolveSQLScriptName("we.sql", "23.5.1")
	if err != nil {
		t.Fatalf("ResolveSQLScriptName: %v", err)
	}
	if got != "we_23.5.sql" {
		t.Fatalf("ResolveSQLScriptName(we.sql) = %q, want we_23.5.sql", got)
	}

	got, err = ResolveSQLScriptName("we.sql", "23.4.0")
	if err != nil {
		t.Fatalf("ResolveSQLScriptName fallback: %v", err)
	}
	if got != "we.sql" {
		t.Fatalf("ResolveSQLScriptName(we.sql, 23.4) = %q, want we.sql", got)
	}

	got, err = ResolveSQLScriptName("we_23.5.sql", "23.5.1")
	if err != nil || got != "we_23.5.sql" {
		t.Fatalf("explicit versioned name = %q, err=%v", got, err)
	}
}

func TestScriptMatchesVersionSupported(t *testing.T) {
	meta := scriptVersionMeta{
		Constraints: parseSupportedSpec("23.4,23.5"),
	}
	if !scriptMatchesVersion(meta, "23.5.2") {
		t.Fatal("expected supported match")
	}
	if scriptMatchesVersion(meta, "24.0.0") {
		t.Fatal("expected supported mismatch")
	}
}

func TestScriptMatchesVersionRange(t *testing.T) {
	meta := scriptVersionMeta{
		Constraints: parseSupportedSpec("23.5-23.99"),
	}
	if !scriptMatchesVersion(meta, "23.5.1") {
		t.Fatal("expected range match")
	}
	if scriptMatchesVersion(meta, "24.0.0") {
		t.Fatal("expected range mismatch")
	}
}
