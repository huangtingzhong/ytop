package connector

import "testing"

func TestFormatMySQLCLIInvocationSplitsConnectFlags(t *testing.T) {
	got := FormatMySQLCLIInvocation("mysql", "-uroot -phuangyihan -h127.0.0.1 -P3306")
	want := "'mysql' '-t' '-uroot' '-phuangyihan' '-h127.0.0.1' '-P3306'"
	if got != want {
		t.Fatalf("FormatMySQLCLIInvocation() = %q, want %q", got, want)
	}
}

func TestFormatMySQLCLIInvocationEmptyConnect(t *testing.T) {
	got := FormatMySQLCLIInvocation("mysql", "")
	want := "'mysql' '-t'"
	if got != want {
		t.Fatalf("FormatMySQLCLIInvocation() = %q, want %q", got, want)
	}
}

func TestFormatMySQLScriptRedirect(t *testing.T) {
	got := FormatMySQLScriptRedirect("mysql", "-uroot -h127.0.0.1", "/tmp/a.sql")
	want := "'mysql' '-t' '-uroot' '-h127.0.0.1' < '/tmp/a.sql'"
	if got != want {
		t.Fatalf("FormatMySQLScriptRedirect() = %q, want %q", got, want)
	}
}

func TestMySQLExecArgvIncludesTableFlag(t *testing.T) {
	got := MySQLExecArgv("-uroot -h127.0.0.1", "-e", "select 1")
	want := []string{"-t", "-uroot", "-h127.0.0.1", "-e", "select 1"}
	if len(got) != len(want) {
		t.Fatalf("MySQLExecArgv() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("MySQLExecArgv()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
