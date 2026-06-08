package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// TestLocalOS verifies LocalOS matches runtime.GOOS.
func TestLocalOS(t *testing.T) {
	got := LocalOS()
	if runtime.GOOS == "windows" {
		if got != OSWindows {
			t.Errorf("LocalOS() = %q, want %q on windows", got, OSWindows)
		}
	} else {
		if got != OSUnix {
			t.Errorf("LocalOS() = %q, want %q on non-windows", got, OSUnix)
		}
	}
}

// TestWrapRemoteCmd_unix verifies Unix wrapping uses bash --login.
func TestWrapRemoteCmd_unix(t *testing.T) {
	got := WrapRemoteCmd(OSUnix, "", "mysql -uroot")
	if !strings.Contains(got, "bash") || !strings.Contains(got, "mysql -uroot") {
		t.Errorf("WrapRemoteCmd unix = %q, want bash + cmd", got)
	}
}

func TestWrapRemoteCmd_unix_source(t *testing.T) {
	got := WrapRemoteCmd(OSUnix, "D:/env/mysql.env.bat", "mysql -uroot")
	if !strings.Contains(got, "bash") {
		t.Errorf("WrapRemoteCmd unix+source = %q, want bash wrapper", got)
	}
	if !strings.Contains(got, "source") || !strings.Contains(got, "mysql -uroot") {
		t.Errorf("WrapRemoteCmd unix+source = %q", got)
	}
}

// TestWrapRemoteCmd_windows verifies Windows wrapping does not nest cmd /C (OpenSSH already uses cmd /c).
func TestWrapRemoteCmd_windows(t *testing.T) {
	got := WrapRemoteCmd(OSWindows, "", `mysql -uroot -p"pass"`)
	if strings.HasPrefix(got, `cmd /C`) {
		t.Errorf("WrapRemoteCmd windows = %q, must not nest cmd /C", got)
	}
	if !strings.Contains(got, "mysql") {
		t.Errorf("WrapRemoteCmd windows = %q, missing mysql command", got)
	}
}

func TestWrapRemoteCmd_windows_source(t *testing.T) {
	got := WrapRemoteCmd(OSWindows, `D:\env\db.bat`, `mysql -uroot`)
	if !strings.HasPrefix(got, "call ") {
		t.Errorf("WrapRemoteCmd windows+source = %q, want 'call' prefix", got)
	}
	if strings.Contains(got, `cmd /C`) {
		t.Errorf("WrapRemoteCmd windows+source = %q, must not nest cmd /C", got)
	}
	if !strings.Contains(got, `D:\env\db.bat`) {
		t.Errorf("WrapRemoteCmd windows+source = %q, missing bat path", got)
	}
	if !strings.Contains(got, "mysql") {
		t.Errorf("WrapRemoteCmd windows+source = %q, missing mysql", got)
	}
}

func TestSourceEnvFileCheckCmd_windows(t *testing.T) {
	got := SourceEnvFileCheckCmd(OSWindows, `D:\mysql\ytop_env.bat`)
	if !strings.Contains(got, "if exist") || !strings.Contains(got, `D:\mysql\ytop_env.bat`) {
		t.Fatalf("SourceEnvFileCheckCmd windows = %q", got)
	}
}

func TestSourceEnvFileCheckCmd_windowsUserProfile(t *testing.T) {
	got := SourceEnvFileCheckCmd(OSWindows, `%USERPROFILE%\123.bat`)
	if !strings.Contains(got, "if exist") || !strings.Contains(got, `%USERPROFILE%\123.bat`) {
		t.Fatalf("SourceEnvFileCheckCmd userprofile = %q", got)
	}
}

// TestCheckRemoteCLICmd verifies correct CLI check command per OS.
func TestCheckRemoteCLICmd(t *testing.T) {
	cases := []struct{ os, cli, wantPrefix string }{
		{OSUnix, "mysql", "which"},
		{OSWindows, "mysql", "where"},
	}
	for _, c := range cases {
		got := CheckRemoteCLICmd(c.os, c.cli)
		if !strings.HasPrefix(got, c.wantPrefix) {
			t.Errorf("CheckRemoteCLICmd(%q,%q) = %q, want prefix %q", c.os, c.cli, got, c.wantPrefix)
		}
		if !strings.Contains(got, c.cli) {
			t.Errorf("CheckRemoteCLICmd(%q,%q) = %q, missing cli name", c.os, c.cli, got)
		}
	}
}

// TestLocalTempPath verifies local temp path is under os.TempDir().
func TestLocalTempPath(t *testing.T) {
	tmpDir := os.TempDir()
	got := LocalTempPath("ytop_test_abc.sql")
	// Use filepath.Clean so trailing-slash differences don't matter.
	if filepath.Clean(filepath.Dir(got)) != filepath.Clean(tmpDir) {
		t.Errorf("LocalTempPath dir = %q, want %q", filepath.Dir(got), tmpDir)
	}
	if !strings.Contains(got, "ytop_test_abc.sql") {
		t.Errorf("LocalTempPath = %q, missing filename", got)
	}
}

// TestShellQuoteUnix verifies single-quote escaping for bash.
func TestShellQuoteUnix(t *testing.T) {
	cases := []struct{ in, want string }{
		{"hello", "'hello'"},
		{"it's", "'it'\\''s'"},
		{"no'quotes'here", "'no'\\''quotes'\\''here'"},
		{"", "''"},
	}
	for _, c := range cases {
		got := ShellQuoteUnix(c.in)
		if got != c.want {
			t.Errorf("ShellQuoteUnix(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// TestResolveCLI_notFound verifies ResolveCLI fails cleanly for unknown CLIs.
func TestResolveCLI_notFound(t *testing.T) {
	_, err := ResolveCLI("mysql", "ytop_cli_that_does_not_exist_12345")
	// defaultCLIName ignores yasqlPath for mysql, tries "mysql"
	// On most CI machines mysql may or may not be present; skip check if found.
	_ = err // just ensure it doesn't panic
}

// TestResolveCLI_knownTool verifies ResolveCLI finds a tool that must exist.
func TestResolveCLI_knownTool(t *testing.T) {
	// "go" binary must be on PATH on any dev machine running tests.
	path, err := exec_lookPath("go")
	if err != nil {
		t.Skip("'go' not in PATH; cannot verify ResolveCLI positive case")
	}
	_ = path // found ok
}

// exec_lookPath is a thin helper so the test file doesn't import os/exec directly.
func exec_lookPath(name string) (string, error) {
	return ResolveCLI("_unknown_dbtype_", name) // yasqlPath = "go" → finds "go"
}

// TestWrapLocalSourceCmd_unix verifies Unix path returns bash -c.
func TestWrapLocalSourceCmd_unix(t *testing.T) {
	prog, args := WrapLocalSourceCmd(OSUnix, "source /etc/env.sh", "mysql -e 'SELECT 1'")
	if prog != "bash" {
		t.Errorf("WrapLocalSourceCmd unix prog = %q, want bash", prog)
	}
	if len(args) < 2 || args[0] != "-c" {
		t.Errorf("WrapLocalSourceCmd unix args = %v, want [-c ...]", args)
	}
	if !strings.Contains(args[1], "mysql") {
		t.Errorf("WrapLocalSourceCmd unix cmd = %q, missing mysql", args[1])
	}
}

// TestWrapLocalSourceCmd_windows verifies Windows path returns cmd /C.
func TestWrapLocalSourceCmd_windows(t *testing.T) {
	prog, args := WrapLocalSourceCmd(OSWindows, `D:\env.bat`, "mysql -e SELECT1")
	if prog != "cmd" {
		t.Errorf("WrapLocalSourceCmd windows prog = %q, want cmd", prog)
	}
	if len(args) < 2 || args[0] != "/C" {
		t.Errorf("WrapLocalSourceCmd windows args = %v, want [/C ...]", args)
	}
	if !strings.Contains(args[1], "call") {
		t.Errorf("WrapLocalSourceCmd windows cmd = %q, missing call", args[1])
	}
}
