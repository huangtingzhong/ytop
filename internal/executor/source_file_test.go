package executor

import (
	"strings"
	"testing"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/platform"
	"github.com/yihan/ytop/internal/scripts"
)

func TestParseSourceInvocation(t *testing.T) {
	tests := []struct {
		in     string
		source string
		args   []string
		kind   scripts.SourceKind
		ok     bool
	}{
		{"memtest.c -i 1 -t 2", "memtest.c", []string{"-i", "1", "-t", "2"}, scripts.SourceKindC, true},
		{"hello.py --verbose", "hello.py", []string{"--verbose"}, scripts.SourceKindPy, true},
		{"./tools/x.c", "./tools/x.c", nil, scripts.SourceKindC, true},
		{"iostat 1 3", "", nil, scripts.SourceKindNone, false},
		{"we.sql", "", nil, scripts.SourceKindNone, false},
	}
	for _, tt := range tests {
		source, args, kind, ok := parseSourceInvocation(tt.in)
		if ok != tt.ok {
			t.Fatalf("parseSourceInvocation(%q) ok=%v want %v", tt.in, ok, tt.ok)
		}
		if !ok {
			continue
		}
		if source != tt.source {
			t.Fatalf("source = %q, want %q", source, tt.source)
		}
		if kind != tt.kind {
			t.Fatalf("kind = %v, want %v", kind, tt.kind)
		}
		if len(args) != len(tt.args) {
			t.Fatalf("args = %v, want %v", args, tt.args)
		}
		for i := range args {
			if args[i] != tt.args[i] {
				t.Fatalf("args[%d] = %q, want %q", i, args[i], tt.args[i])
			}
		}
	}
}

func TestBuildSourceRunUnixC(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.LDFLAGS = "-lm"
	cmd := buildSourceRunUnix(cfgDefaults(cfg), "/tmp", "/tmp/ytop_test.c", "/tmp/ytop_test", scripts.SourceKindC, []string{"-i", "1"})
	if !strings.Contains(cmd, "gcc") {
		t.Fatalf("missing gcc: %s", cmd)
	}
	if !strings.Contains(cmd, "-lm") {
		t.Fatalf("missing -lm: %s", cmd)
	}
	if !strings.Contains(cmd, "'-i'") || !strings.Contains(cmd, "'1'") {
		t.Fatalf("missing run args: %s", cmd)
	}
}

func TestBuildSourceRunUnixPy(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Python = "/opt/venv/bin/python3"
	cmd := buildSourceRunUnix(cfgDefaults(cfg), "/tmp", "/tmp/ytop_test.py", "", scripts.SourceKindPy, []string{"--once"})
	if !strings.Contains(cmd, "/opt/venv/bin/python3") {
		t.Fatalf("missing python path: %s", cmd)
	}
	if !strings.Contains(cmd, " -u ") {
		t.Fatalf("missing python -u unbuffered flag: %s", cmd)
	}
	if !strings.Contains(cmd, "'--once'") {
		t.Fatalf("missing run arg: %s", cmd)
	}
}

func TestBuildSourceRunWindowsC(t *testing.T) {
	cfg := config.DefaultConfig()
	cmd := buildSourceRunWindows(cfgDefaults(cfg), `C:\Temp`, `C:\Temp\ytop_test.c`, `C:\Temp\ytop_test.exe`, scripts.SourceKindC, nil)
	if !strings.Contains(cmd, "cd /d") {
		t.Fatalf("missing cd /d: %s", cmd)
	}
	if platform.OSWindows != "windows" {
		t.Skip("windows-specific")
	}
}
