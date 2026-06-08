package platform

import "testing"

func TestRemoteScriptPaths_windows(t *testing.T) {
	sftp, exec := RemoteScriptPaths(OSWindows, `C:\Users\admin\AppData\Local\Temp`, "ytop_1.sql")
	if exec != "C:/Users/admin/AppData/Local/Temp/ytop_1.sql" {
		t.Fatalf("exec path = %q", exec)
	}
	if sftp != "/C:/Users/admin/AppData/Local/Temp/ytop_1.sql" {
		t.Fatalf("sftp path = %q, want /C:/ prefix for OpenSSH SFTP", sftp)
	}
}

func TestRemoteScriptPaths_unix(t *testing.T) {
	sftp, exec := RemoteScriptPaths(OSUnix, "/tmp", "ytop_1.sql")
	want := "/tmp/ytop_1.sql"
	if sftp != want || exec != want {
		t.Fatalf("sftp=%q exec=%q, want %q", sftp, exec, want)
	}
}

func TestSFTPPath_windows(t *testing.T) {
	got := SFTPPath(OSWindows, `C:\Users\admin\AppData\Local\Temp`, "ytop_1.sql")
	want := "/C:/Users/admin/AppData/Local/Temp/ytop_1.sql"
	if got != want {
		t.Fatalf("SFTPPath() = %q, want %q", got, want)
	}
}

func TestParseRemoteTempOutput_windows(t *testing.T) {
	got := ParseRemoteTempOutput(OSWindows, "C:\\Users\\admin\\AppData\\Local\\Temp\r\n")
	if got != `C:\Users\admin\AppData\Local\Temp` {
		t.Fatalf("ParseRemoteTempOutput windows = %q", got)
	}
}

func TestParseRemoteTempOutput_unix(t *testing.T) {
	got := ParseRemoteTempOutput(OSUnix, "/tmp\n")
	if got != "/tmp" {
		t.Fatalf("ParseRemoteTempOutput unix = %q", got)
	}
}

func TestParseRemoteTempOutput_emptyUsesDefault(t *testing.T) {
	if got := ParseRemoteTempOutput(OSWindows, ""); got != `C:\Windows\Temp` {
		t.Fatalf("default windows temp = %q", got)
	}
	if got := ParseRemoteTempOutput(OSUnix, ""); got != "/tmp" {
		t.Fatalf("default unix temp = %q", got)
	}
}
