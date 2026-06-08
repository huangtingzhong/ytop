package connector

import (
	"strings"
	"testing"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/platform"
)

// Black-box tests for remote SQL command construction (no live SSH/DB).

func TestBuildRemoteSQLExecCmd_mysql_unix(t *testing.T) {
	cfg := &config.Config{DBType: "mysql", ConnectString: "-uroot -h127.0.0.1 -P3306"}
	got := BuildRemoteSQLExecCmd(cfg, platform.OSUnix, "/tmp/ytop.sql")
	if !strings.Contains(got, "mysql") || !strings.Contains(got, "/tmp/ytop.sql") {
		t.Fatalf("BuildRemoteSQLExecCmd unix = %q", got)
	}
	if !strings.Contains(got, "<") {
		t.Fatalf("expected shell redirect, got %q", got)
	}
}

func TestBuildRemoteSQLExecCmd_mysql_windows(t *testing.T) {
	cfg := &config.Config{
		DBType:        "mysql",
		ConnectString: "-t -uroot -h127.0.0.1 -P3307",
		RemoteCLIPath: `D:\mysql\bin\mysql.exe`,
	}
	got := BuildRemoteSQLExecCmd(cfg, platform.OSWindows, `C:\Temp\ytop.sql`)
	if !strings.Contains(got, `D:\mysql\bin\mysql.exe`) {
		t.Fatalf("BuildRemoteSQLExecCmd windows = %q, want resolved mysql path", got)
	}
	if !strings.Contains(got, `source C:/Temp/ytop.sql`) {
		t.Fatalf("BuildRemoteSQLExecCmd windows = %q, want mysql source command", got)
	}
	if !strings.Contains(got, "-P3307") {
		t.Fatalf("BuildRemoteSQLExecCmd windows = %q, want connect port preserved", got)
	}
	if strings.Contains(got, `--protocol=PIPE`) {
		t.Fatalf("BuildRemoteSQLExecCmd windows = %q, must not force PIPE", got)
	}
}

func TestBuildRemoteSQLExecCmd_oracle(t *testing.T) {
	cfg := &config.Config{DBType: "oracle", ConnectString: "/ as sysdba"}
	got := BuildRemoteSQLExecCmd(cfg, platform.OSUnix, "/tmp/q.sql")
	if want := "sqlplus -S / as sysdba @/tmp/q.sql"; got != want {
		t.Fatalf("BuildRemoteSQLExecCmd oracle = %q, want %q", got, want)
	}
}

