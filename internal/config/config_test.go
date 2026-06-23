package config

import "testing"

func TestApplyMssqlSSHWindowsConnectDefaults(t *testing.T) {
	cfg := &Config{
		DBType:         "mssql",
		ConnectionMode: "ssh",
		TargetOS:       "windows",
		ConnectString:  "",
	}
	cfg.ApplyMssqlSSHWindowsConnectDefaults()
	if cfg.ConnectString != defaultMssqlSSHWindowsConnectString {
		t.Fatalf("ConnectString = %q, want %q", cfg.ConnectString, defaultMssqlSSHWindowsConnectString)
	}
}

func TestApplyMssqlSSHWindowsConnectDefaults_skipsWhenConnectSet(t *testing.T) {
	cfg := &Config{
		DBType:         "mssql",
		ConnectionMode: "ssh",
		TargetOS:       "windows",
		ConnectString:  "-S localhost -U sa -P secret",
	}
	cfg.ApplyMssqlSSHWindowsConnectDefaults()
	if cfg.ConnectString != "-S localhost -U sa -P secret" {
		t.Fatalf("ConnectString should be preserved, got %q", cfg.ConnectString)
	}
}

func TestApplyMssqlSSHWindowsConnectDefaults_skipsUnixSSH(t *testing.T) {
	cfg := &Config{
		DBType:         "mssql",
		ConnectionMode: "ssh",
		TargetOS:       "unix",
		ConnectString:  "",
	}
	cfg.ApplyMssqlSSHWindowsConnectDefaults()
	if cfg.ConnectString != "" {
		t.Fatalf("ConnectString = %q, want empty on unix SSH", cfg.ConnectString)
	}
}

func TestApplyMssqlSSHWindowsConnectDefaults_skipsLoginCmd(t *testing.T) {
	cfg := &Config{
		DBType:         "mssql",
		ConnectionMode: "ssh",
		TargetOS:       "windows",
		ConnectString:  "",
		LoginCmd:       "sqlcmd -S localhost -U sa",
	}
	cfg.ApplyMssqlSSHWindowsConnectDefaults()
	if cfg.ConnectString != "" {
		t.Fatalf("ConnectString = %q, want empty when LoginCmd is set", cfg.ConnectString)
	}
}

func TestApplyDBTypeConnectDefaults_mssqlClearsOracleConnect(t *testing.T) {
	cfg := &Config{DBType: "mssql", ConnectString: "/ as sysdba"}
	cfg.ApplyDBTypeConnectDefaults()
	if cfg.ConnectString != "" {
		t.Fatalf("ConnectString = %q, want empty after oracle-style cleanup", cfg.ConnectString)
	}
}

func TestApplyMssqlRegistryPort(t *testing.T) {
	cfg := &Config{
		DBType:         "mssql",
		ConnectionMode: "ssh",
		TargetOS:       "windows",
		ConnectString:  defaultMssqlSSHWindowsConnectString,
	}
	cfg.ApplyMssqlRegistryPort("1433")
	if cfg.ConnectString != defaultMssqlSSHWindowsConnectString {
		t.Fatalf("1433 should not change connect string, got %q", cfg.ConnectString)
	}
	cfg.ApplyMssqlRegistryPort("14333")
	if cfg.ConnectString != "-S localhost,14333 -E" {
		t.Fatalf("ConnectString = %q, want port patch", cfg.ConnectString)
	}
}
