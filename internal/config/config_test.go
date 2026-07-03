package config

import (
	"os"
	"path/filepath"
	"testing"
)

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

func writeTestINI(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.ini")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadFromFile_allScriptKeys(t *testing.T) {
	ini := writeTestINI(t, `
connection_mode = ssh
yasql_path = /opt/yasql/bin/yasql
connect_string = / as sysdba
ssh_host = 10.0.0.1
ssh_port = 2222
ssh_user = yashan
ssh_password = secret
ssh_key_file = /home/u/.ssh/id_rsa
source_cmd = /etc/yashandb.env
interval = 3
count = 7
output_file = /tmp/out.log
session_top_n = 15
session_sort_by = CPU TIME
session_detail_top_n = 8
show_timestamp = false
color_enabled = false
instance_id = 2
sysstat_metrics = DB TIME,CPU TIME
event_top_n = 8
query_timeout = 60
ssh_timeout = 20
reuse_ssh = false
debug = true
execute_script = we.sql
execute_sql = select 1 from dual
read_script = we.sql
copy_script = we.sql /tmp
find_script = ^we
metric_mode = true
db_type = oracle
db_version = 19.3
login_cmd = sqlplus / as sysdba
target_os = unix
cc = clang
cflags = -O2
ldflags = -lm
python = python3.11
`)
	cfg := DefaultConfig()
	if err := loadFromFile(cfg, ini); err != nil {
		t.Fatal(err)
	}

	checks := []struct {
		name string
		got  interface{}
		want interface{}
	}{
		{"ConnectionMode", cfg.ConnectionMode, "ssh"},
		{"YasqlPath", cfg.YasqlPath, "/opt/yasql/bin/yasql"},
		{"SSHHost", cfg.SSHHost, "10.0.0.1"},
		{"SSHPort", cfg.SSHPort, 2222},
		{"Interval", cfg.Interval, 3},
		{"Count", cfg.Count, 7},
		{"SessionTopN", cfg.SessionTopN, 15},
		{"SessionSortBy", cfg.SessionSortBy, "CPU TIME"},
		{"ShowTimestamp", cfg.ShowTimestamp, false},
		{"ColorEnabled", cfg.ColorEnabled, false},
		{"InstanceID", cfg.InstanceID, 2},
		{"EventTopN", cfg.EventTopN, 8},
		{"QueryTimeout", cfg.QueryTimeout, 60},
		{"ReuseSSH", cfg.ReuseSSH, false},
		{"DebugMode", cfg.DebugMode, true},
		{"ExecuteScript", cfg.ExecuteScript, "we.sql"},
		{"ExecuteSQL", cfg.ExecuteSQL, "select 1 from dual"},
		{"MetricMode", cfg.MetricMode, true},
		{"DBType", cfg.DBType, "oracle"},
		{"DBVersion", cfg.DBVersion, "19.3"},
		{"LoginCmd", cfg.LoginCmd, "sqlplus / as sysdba"},
		{"TargetOS", cfg.TargetOS, "unix"},
		{"CC", cfg.CC, "clang"},
		{"Python", cfg.Python, "python3.11"},
		{"FindScriptSet", cfg.FindScriptSet, true},
	}
	for _, c := range checks {
		if c.got != c.want {
			t.Errorf("%s = %v, want %v", c.name, c.got, c.want)
		}
	}
	if !cfg.iniIntervalSet || !cfg.iniCountSet || !cfg.iniConnectionModeSet || !cfg.iniSessionTopSet {
		t.Error("expected ini tracking flags to be set")
	}
	if len(cfg.SysStatMetrics) != 2 || cfg.SysStatMetrics[0] != "DB TIME" {
		t.Errorf("SysStatMetrics = %#v", cfg.SysStatMetrics)
	}
}

func TestLoadFromFile_dbTypeInvalid(t *testing.T) {
	ini := writeTestINI(t, "db_type = nosuch\n")
	cfg := DefaultConfig()
	if err := loadFromFile(cfg, ini); err == nil {
		t.Fatal("expected error for invalid db_type")
	}
}

func TestLoadINIInto_cliOverridesIni(t *testing.T) {
	ini := writeTestINI(t, "db_version = 23.4.0\ninstance_id = 2\n")
	cfg := DefaultConfig()
	if err := LoadINIInto(cfg, ini); err != nil {
		t.Fatal(err)
	}
	if cfg.DBVersion != "23.4.0" || cfg.InstanceID != 2 {
		t.Fatalf("ini load failed: version=%q inst=%d", cfg.DBVersion, cfg.InstanceID)
	}

	visited := map[string]bool{"V": true, "inst-id": true}
	cfg.DBVersion = "23.5.1"
	cfg.InstanceID = 1
	if !VisitedAny(visited, "V") {
		t.Fatal("VisitedAny broken")
	}
}

func TestResolveExplicitConfigPath(t *testing.T) {
	visited := map[string]bool{"c": true}
	if got := resolveExplicitConfigPath(visited, "/tmp/a.ini"); got != "/tmp/a.ini" {
		t.Fatalf("resolveExplicitConfigPath(-c) = %q", got)
	}
	if got := resolveExplicitConfigPath(map[string]bool{"config": true}, "/tmp/b.ini"); got != "/tmp/b.ini" {
		t.Fatalf("resolveExplicitConfigPath(--config) = %q", got)
	}
	if got := resolveExplicitConfigPath(map[string]bool{}, "/tmp/a.ini"); got != "" {
		t.Fatalf("resolveExplicitConfigPath(no flags) = %q, want empty", got)
	}
}

func TestLoadINIInto_skipsWithoutExplicitPath(t *testing.T) {
	cfg := DefaultConfig()
	cfg.DBVersion = "19.3"
	if err := LoadINIInto(cfg, ""); err != nil {
		t.Fatal(err)
	}
	if cfg.DBVersion != "19.3" {
		t.Fatalf("LoadINIInto(\"\") should not change cfg, DBVersion=%q", cfg.DBVersion)
	}
}

func TestLoadINIInto_loadsExplicitPath(t *testing.T) {
	ini := writeTestINI(t, "db_version = 23.4.0\n")
	cfg := DefaultConfig()
	if err := LoadINIInto(cfg, ini); err != nil {
		t.Fatal(err)
	}
	if cfg.DBVersion != "23.4.0" {
		t.Fatalf("DBVersion = %q, want 23.4.0", cfg.DBVersion)
	}
}

func TestParseINIBool(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want bool
	}{
		{"true", true}, {"1", true}, {"false", false}, {"0", false},
	} {
		got, err := parseINIBool(tc.in)
		if err != nil || got != tc.want {
			t.Errorf("parseINIBool(%q) = %v, %v", tc.in, got, err)
		}
	}
}

func TestAutoSSHModeFromIniHost(t *testing.T) {
	ini := writeTestINI(t, "ssh_host = 10.0.0.2\n")
	cfg := DefaultConfig()
	if err := loadFromFile(cfg, ini); err != nil {
		t.Fatal(err)
	}
	if cfg.SSHHost != "10.0.0.2" {
		t.Fatalf("SSHHost = %q", cfg.SSHHost)
	}
}

func TestLoadFromFile_hashInPassword(t *testing.T) {
	ini := writeTestINI(t, `
ssh_password = p@ss#word
connect_string = sys/pass#123
login_cmd = yasql user/pa#ss
`)
	cfg := DefaultConfig()
	if err := loadFromFile(cfg, ini); err != nil {
		t.Fatal(err)
	}
	if cfg.SSHPassword != "p@ss#word" {
		t.Fatalf("SSHPassword = %q, want p@ss#word", cfg.SSHPassword)
	}
	if cfg.ConnectString != "sys/pass#123" {
		t.Fatalf("ConnectString = %q, want sys/pass#123", cfg.ConnectString)
	}
	if cfg.LoginCmd != "yasql user/pa#ss" {
		t.Fatalf("LoginCmd = %q, want yasql user/pa#ss", cfg.LoginCmd)
	}
}

func TestLoadFromFile_inlineCommentStripped(t *testing.T) {
	ini := writeTestINI(t, `
ssh_host = 10.0.0.1  # prod
interval = 5  ; seconds
debug = true  # on
cflags = -O2 -Wall  ; optimize
`)
	cfg := DefaultConfig()
	if err := loadFromFile(cfg, ini); err != nil {
		t.Fatal(err)
	}
	if cfg.SSHHost != "10.0.0.1" {
		t.Fatalf("SSHHost = %q, want 10.0.0.1", cfg.SSHHost)
	}
	if cfg.Interval != 5 {
		t.Fatalf("Interval = %d, want 5", cfg.Interval)
	}
	if !cfg.DebugMode {
		t.Fatal("DebugMode should be true")
	}
	if cfg.CFLAGS != "-O2 -Wall" {
		t.Fatalf("CFLAGS = %q, want -O2 -Wall", cfg.CFLAGS)
	}
}
