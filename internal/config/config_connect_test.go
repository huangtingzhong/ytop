package config

import "testing"

func TestApplyDBTypeConnectDefaultsMySQLClearsSysdba(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DBType = "mysql"
	cfg.ConnectString = "/ as sysdba"

	cfg.ApplyDBTypeConnectDefaults()

	if cfg.ConnectString != "" {
		t.Fatalf("ConnectString = %q, want empty for mysql", cfg.ConnectString)
	}
}

func TestApplyDBTypeConnectDefaultsMySQLKeepsCustomConnect(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DBType = "mysql"
	cfg.ConnectString = "-uroot -p -h127.0.0.1 -P3306"

	cfg.ApplyDBTypeConnectDefaults()

	if cfg.ConnectString != "-uroot -p -h127.0.0.1 -P3306" {
		t.Fatalf("ConnectString = %q, want custom mysql flags preserved", cfg.ConnectString)
	}
}

func TestApplyDBTypeConnectDefaultsOracleKeepsSysdba(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DBType = "oracle"
	cfg.ConnectString = "/ as sysdba"

	cfg.ApplyDBTypeConnectDefaults()

	if cfg.ConnectString != "/ as sysdba" {
		t.Fatalf("ConnectString = %q, want / as sysdba for oracle", cfg.ConnectString)
	}
}

func TestApplyDBTypeConnectDefaultsSkipsWhenLoginCmdSet(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DBType = "mysql"
	cfg.ConnectString = "/ as sysdba"
	cfg.LoginCmd = "mysql -uroot -p"

	cfg.ApplyDBTypeConnectDefaults()

	if cfg.ConnectString != "/ as sysdba" {
		t.Fatalf("ConnectString = %q, want unchanged when LoginCmd is set", cfg.ConnectString)
	}
}
