package platform

import (
	"strings"
	"testing"
)

func TestOSScriptKindFromExt(t *testing.T) {
	cases := []struct {
		file string
		want OSScriptKind
	}{
		{"sar.sh", OSScriptKindBash},
		{"win_counter.ps1", OSScriptKindPowerShell},
		{"run.bat", OSScriptKindCmd},
		{"pidstat.py", OSScriptKindPython},
		{"unknown", OSScriptKindUnknown},
	}
	for _, tc := range cases {
		if got := OSScriptKindFromExt(tc.file); got != tc.want {
			t.Fatalf("OSScriptKindFromExt(%q) = %v, want %v", tc.file, got, tc.want)
		}
	}
}

func TestOSScriptSupportedOn_mismatch(t *testing.T) {
	if OSScriptSupportedOn(OSScriptKindPowerShell, OSUnix) {
		t.Fatal("powershell should not run on unix")
	}
	if OSScriptSupportedOn(OSScriptKindBash, OSWindows) {
		t.Fatal("bash script should not run on windows")
	}
	if !OSScriptSupportedOn(OSScriptKindPython, OSWindows) {
		t.Fatal("python should run on windows")
	}
}

func TestOSScriptMismatchError(t *testing.T) {
	err := OSScriptMismatchError("sar.sh", OSWindows, OSScriptKindBash)
	if err == nil || !strings.Contains(err.Error(), "requires unix") {
		t.Fatalf("unexpected error: %v", err)
	}
	err = OSScriptMismatchError("win_counter.ps1", OSUnix, OSScriptKindPowerShell)
	if err == nil || !strings.Contains(err.Error(), "requires windows") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestBuildOSScriptRunCmd_unixBash(t *testing.T) {
	got, err := BuildOSScriptRunCmd(OSUnix, "/tmp/ytop_sar.sh", []string{"1", "2"}, OSScriptKindBash, "")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "bash '/tmp/ytop_sar.sh'") {
		t.Fatalf("BuildOSScriptRunCmd unix bash = %q", got)
	}
}

func TestBuildOSScriptRunCmd_windowsPowerShell(t *testing.T) {
	got, err := BuildOSScriptRunCmd(OSWindows, `C:\Temp\ytop_win_counter.ps1`, nil, OSScriptKindPowerShell, "")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "powershell") || !strings.Contains(got, "win_counter.ps1") {
		t.Fatalf("BuildOSScriptRunCmd windows ps1 = %q", got)
	}
}

func TestBuildOSScriptRunCmd_windowsCmd(t *testing.T) {
	got, err := BuildOSScriptRunCmd(OSWindows, `C:\Temp\run.bat`, nil, OSScriptKindCmd, "")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "call") || !strings.Contains(got, "run.bat") {
		t.Fatalf("BuildOSScriptRunCmd windows bat = %q", got)
	}
}
