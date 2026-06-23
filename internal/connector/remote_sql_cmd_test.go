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

func TestBuildRemoteSQLExecCmd_mssql_unix(t *testing.T) {
	cfg := &config.Config{
		DBType:        "mssql",
		ConnectString: "-S localhost -U sa -P secret -d master",
	}
	got := BuildRemoteSQLExecCmd(cfg, platform.OSUnix, "/tmp/ytop.sql")
	if !strings.Contains(got, "sqlcmd") || !strings.Contains(got, "-i") || !strings.Contains(got, "/tmp/ytop.sql") {
		t.Fatalf("BuildRemoteSQLExecCmd mssql unix = %q", got)
	}
}

func TestBuildRemoteSQLExecCmd_mssql_windows(t *testing.T) {
	cfg := &config.Config{
		DBType:        "mssql",
		ConnectString: "-S localhost -E",
		RemoteCLIPath: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe`,
	}
	got := BuildRemoteSQLExecCmd(cfg, platform.OSWindows, `C:\Users\Administrator\AppData\Local\Temp\ytop.sql`)
	if !strings.Contains(got, "sqlcmd.exe") {
		t.Fatalf("BuildRemoteSQLExecCmd mssql windows = %q, want sqlcmd path", got)
	}
	if !strings.Contains(got, "-i") || !strings.Contains(got, `\Temp\ytop.sql`) {
		t.Fatalf("BuildRemoteSQLExecCmd mssql windows = %q, want -i with backslash path", got)
	}
	if strings.Contains(got, "/Users") {
		t.Fatalf("BuildRemoteSQLExecCmd mssql windows = %q, must not use forward slashes in Users path", got)
	}
}

func TestFormatSQLCmdAdHocRemoteCmd_windows(t *testing.T) {
	got := FormatSQLCmdAdHocRemoteCmd(
		platform.OSWindows,
		`C:\Tools\sqlcmd.exe`,
		"-S localhost -U sa",
		"SELECT 1",
	)
	if !strings.Contains(got, `-Q`) || !strings.Contains(got, "SELECT 1") {
		t.Fatalf("FormatSQLCmdAdHocRemoteCmd windows = %q", got)
	}
}
