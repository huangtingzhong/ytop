package executor

import "testing"

func TestEscapeYasqlSubstValue(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"empty", "", ""},
		{"no dollar", "select 1 from dual", "select 1 from dual"},
		{"v session view", "select * from v$session", "select * from v#session"},
		{"gv session", "select * from gv$session where rownum <= 3", "select * from gv#session where rownum <= 3"},
		{"multiple idents", "a$b$c", "a#b#c"},
		{"wrh dollar view", "FROM WRH$_SQLSTAT", "FROM WRH#_SQLSTAT"},
		{"hash without dollar ident", "select * from v#session", "select * from v#session"},
		{"semicolon suffix", "select * from v$session;", "select * from v#session;"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := escapeYasqlSubstValue(tt.input); got != tt.want {
				t.Fatalf("escapeYasqlSubstValue(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}
