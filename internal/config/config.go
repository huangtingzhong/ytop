package config

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"gopkg.in/ini.v1"
)

// Config holds all configuration parameters
type Config struct {
	// Connection settings
	ConnectionMode string // "local" or "ssh"
	YasqlPath      string
	ConnectString  string

	// SSH settings
	SSHHost     string
	SSHPort     int
	SSHUser     string
	SSHPassword string
	SSHKeyFile  string
	SourceCmd string

	// SSHSourceExistenceCheck is a remote `test -f <path>` fragment produced when -s is a simple env file path (SSH mode).
	// Executed once in SSHConnector.Connect; empty when using a custom shell snippet or local mode.
	SSHSourceExistenceCheck string

	// Display settings
	Interval           int
	Count              int
	OutputFile         string
	SessionTopN        int
	SessionSortBy      string
	SessionDetailTopN  int
	ShowTimestamp      bool
	ColorEnabled       bool
	InstanceID         int // 0 = all instances, 1,2,... = specific instance

	// Metric settings
	SysStatMetrics []string
	EventTopN      int

	// Advanced settings
	QueryTimeout   int
	SSHTimeout     int
	ReuseSSH       bool
	DebugMode      bool

	// Direct execution mode (non-interactive)
	ExecuteScript  string // -f: script file to execute
	ExecuteSQL     string // -q: SQL query to execute
	ReadScript     string // -r: read/view script content
	CopyScript     string // -c: copy script (format: "script dest")
	FindScript     string // -S: find/search scripts (pattern; empty means all)
	FindScriptSet  bool   // true when -S was passed on the command line

	// Metric mode (delta/per-second calculation)
	MetricMode bool // --metric: enable metric collection with delta calculation

	// Database type
	DBType string // "yashandb", "oracle", "dameng", "mysql", "postgresql"

	// Custom login command (overrides default CLI login)
	LoginCmd string
}

// DefaultConfig returns a config with default values
func DefaultConfig() *Config {
	return &Config{
		ConnectionMode:    "local", // Default to local mode
		YasqlPath:         "yasql",
		ConnectString:     defaultOracleConnectString,
		SSHPort:           22,
		Interval:          5,
		Count:             0,
		SessionTopN:       10,
		SessionSortBy:     "DB TIME",
		SessionDetailTopN: 10,
		ShowTimestamp:     true,
		ColorEnabled:      true,
		InstanceID:        0, // 0 = all instances
		SysStatMetrics: []string{
			"DB TIME",
			"CPU TIME",
			"COMMITS",
			"REDO SIZE",
			"QUERY COUNT",
			"BLOCK CHANGES",
			"LOGONS TOTAL",
			"INSERT COUNT",
			"PARSE COUNT (HARD)",
			"DISK READS",
			"DISK WRITES",
			"BUFFER GETS",
			"EXECUTE COUNT",
			"BUFFER CR GETS",
		},
		EventTopN:    5,
		QueryTimeout: 30,
		SSHTimeout:   10,
		ReuseSSH:     true,
		DebugMode:    false,
		DBType:       "yashandb",
	}
}

// DefaultCLI returns the default CLI tool name for the given DB type
func (c *Config) DefaultCLI() string {
	switch c.DBType {
	case "oracle":
		return "sqlplus"
	case "dameng":
		return "disql"
	case "mysql":
		return "mysql"
	case "postgresql":
		return "psql"
	default:
		return c.YasqlPath
	}
}

const defaultOracleConnectString = "/ as sysdba"

// IsOracleStyleConnectString reports whether s is an Oracle/YashanDB sqlplus-style connect string.
func IsOracleStyleConnectString(s string) bool {
	trimmed := strings.TrimSpace(s)
	if trimmed == "" {
		return false
	}
	lower := strings.ToLower(trimmed)
	return lower == defaultOracleConnectString ||
		lower == "/ as sysoper" ||
		strings.HasPrefix(lower, "/ as sys")
}

// ApplyDBTypeConnectDefaults adjusts ConnectString for the selected DB CLI.
func (c *Config) ApplyDBTypeConnectDefaults() {
	if c.LoginCmd != "" {
		return
	}
	switch c.DBType {
	case "mysql", "postgresql":
		if IsOracleStyleConnectString(c.ConnectString) {
			c.ConnectString = ""
		}
	}
}

// parseDBType normalizes db type shorthand to canonical name
func parseDBType(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "y", "yas", "yashandb":
		return "yashandb"
	case "o", "ora", "oracle":
		return "oracle"
	case "d", "dm", "dameng":
		return "dameng"
	case "m", "my", "mysql":
		return "mysql"
	case "p", "pg", "postgres", "postgresql":
		return "postgresql"
	default:
		return "yashandb"
	}
}

// normalizeFindScriptFlagArgs turns bare "-S" into "-S" "" so an empty pattern lists all scripts.
func normalizeFindScriptFlagArgs(args []string) []string {
	if len(args) <= 1 {
		return args
	}
	out := make([]string, 0, len(args)+1)
	out = append(out, args[0])
	for i := 1; i < len(args); i++ {
		out = append(out, args[i])
		if args[i] != "-S" {
			continue
		}
		hasValue := i+1 < len(args) && !strings.HasPrefix(args[i+1], "-")
		if !hasValue {
			out = append(out, "")
		}
	}
	return out
}

// LoadConfig loads configuration from file and command line
func LoadConfig() (*Config, error) {
	cfg := DefaultConfig()

	// Customize flag error handling to show our custom usage
	flag.Usage = func() {
		PrintUsage()
	}

	// Define command line flags
	configFile := flag.String("config", "", "Path to config file")
	connectionMode := flag.String("mode", "", "Connection mode: local or ssh")
	yasqlPath := flag.String("yasql", "", "Path to yasql executable")
	connectString := flag.String("connect", "", "Connection string")
	connectStringShort := flag.String("C", "", "Connection string (short)")
	sshHost := flag.String("ssh-host", "", "SSH host")
	sshHostShort := flag.String("t", "", "SSH host (short)")
	port := flag.Int("port", 0, "SSH port")
	portShort := flag.Int("P", 0, "SSH port (short)")
	sshUser := flag.String("ssh-user", "", "SSH user")
	sshUserShort := flag.String("u", "", "SSH user (short)")
	sshPassword := flag.String("ssh-password", "", "SSH password")
	sshPasswordShort := flag.String("p", "", "SSH password (short)")
	sshKeyFile := flag.String("ssh-key", "", "SSH private key file")
	sshKeyFileShort := flag.String("k", "", "SSH private key file (short)")
	sourceCmd := flag.String("source", "", "Source command to run before yasql")
	sourceCmdShort := flag.String("s", "", "Source command (short)")
	// Interval and count are now handled via positional arguments only
	// Removed -i and -c flags for simplicity
	outputFile := flag.String("o", "", "Output file path")
	sessionTopN := flag.Int("session-top", 0, "Number of sessions to show in TOP N")
	sessionSortBy := flag.String("session-sort", "", "Session sort column")
	sessionDetailTopN := flag.Int("session-detail-top", 0, "Number of active sessions to show")
	instanceID := flag.Int("inst-id", 0, "Instance ID (0 = all instances, 1,2,... = specific instance)")
	noColor := flag.Bool("no-color", false, "Disable color output")
	noTimestamp := flag.Bool("no-timestamp", false, "Hide timestamp")
	debug := flag.Bool("debug", false, "Enable debug mode")
	debugShort := flag.Bool("D", false, "Enable debug mode (short)")
	executeScript := flag.String("f", "", "Execute script file directly (non-interactive mode)")
	executeSQL := flag.String("q", "", "Execute SQL query directly (non-interactive mode)")
	readScript := flag.String("r", "", "Read/view script content (non-interactive mode)")
	copyScript := flag.String("copy", "", "Copy script to destination (format: 'script dest', non-interactive mode)")
	findScript := flag.String("S", "", "Find/search scripts by pattern (non-interactive mode)")
	metricMode := flag.Bool("m", false, "Enable metric mode with delta/per-second calculation (use with -f)")
	metricModeLong := flag.Bool("metric", false, "Enable metric mode with delta/per-second calculation (use with -f)")
	dbType := flag.String("d", "", "Database type: y/yas/yashandb, o/ora/oracle, d/dm/dameng, m/my/mysql, p/pg/postgres")
	dbTypeLong := flag.String("db-type", "", "Database type (long form)")
	loginCmd := flag.String("login-cmd", "", "Custom login command (e.g. 'sqlplus / as sysdba')")

	if err := flag.CommandLine.Parse(normalizeFindScriptFlagArgs(os.Args)[1:]); err != nil {
		return nil, err
	}

	// Load from config file if specified
	if *configFile != "" {
		if err := loadFromFile(cfg, *configFile); err != nil {
			return nil, fmt.Errorf("failed to load config file: %w", err)
		}
	}

	// Override with command line flags
	if *connectionMode != "" {
		cfg.ConnectionMode = *connectionMode
	}
	if *yasqlPath != "" {
		cfg.YasqlPath = *yasqlPath
	}
	if *connectString != "" {
		cfg.ConnectString = *connectString
	}
	if *connectStringShort != "" {
		cfg.ConnectString = *connectStringShort
	}
	if *sshHost != "" {
		cfg.SSHHost = *sshHost
	}
	if *sshHostShort != "" {
		cfg.SSHHost = *sshHostShort
	}
	if *port != 0 {  // Changed from > 0 to != 0 to handle both positive and default values
		cfg.SSHPort = *port
	}
	if *portShort != 0 {  // Handle short parameter -P
		cfg.SSHPort = *portShort
	}
	if *sshUser != "" {
		cfg.SSHUser = *sshUser
	}
	if *sshUserShort != "" {
		cfg.SSHUser = *sshUserShort
	}
	if *sshPassword != "" {
		cfg.SSHPassword = *sshPassword
	}
	if *sshPasswordShort != "" {
		cfg.SSHPassword = *sshPasswordShort
	}
	if *sshKeyFile != "" {
		cfg.SSHKeyFile = *sshKeyFile
	}
	if *sshKeyFileShort != "" {
		cfg.SSHKeyFile = *sshKeyFileShort
	}
	if *sourceCmd != "" {
		cfg.SourceCmd = *sourceCmd
	}
	if *sourceCmdShort != "" {
		cfg.SourceCmd = *sourceCmdShort
	}
	if *outputFile != "" {
		cfg.OutputFile = *outputFile
	}
	if *sessionTopN > 0 {
		cfg.SessionTopN = *sessionTopN
	}
	if *sessionSortBy != "" {
		cfg.SessionSortBy = *sessionSortBy
	}
	if *sessionDetailTopN > 0 {
		cfg.SessionDetailTopN = *sessionDetailTopN
	}
	if *noColor {
		cfg.ColorEnabled = false
	}
	if *noTimestamp {
		cfg.ShowTimestamp = false
	}
	if *debug || *debugShort {
		cfg.DebugMode = true
	}
	if *instanceID >= 0 {
		cfg.InstanceID = *instanceID
	}
	if *executeScript != "" {
		cfg.ExecuteScript = *executeScript
	}
	if *executeSQL != "" {
		cfg.ExecuteSQL = *executeSQL
	}
	if *readScript != "" {
		cfg.ReadScript = *readScript
	}
	if *copyScript != "" {
		cfg.CopyScript = *copyScript
	}
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "S" {
			cfg.FindScript = *findScript
			cfg.FindScriptSet = true
		}
	})
	if *metricMode || *metricModeLong {
		cfg.MetricMode = true
	}
	if *dbTypeLong != "" {
		cfg.DBType = parseDBType(*dbTypeLong)
	}
	if *dbType != "" {
		cfg.DBType = parseDBType(*dbType)
	}
	if *loginCmd != "" {
		cfg.LoginCmd = *loginCmd
	}

	cfg.ApplyDBTypeConnectDefaults()

	// Auto-detect connection mode based on SSH host (needed before normalizing -s paths)
	// If user explicitly set mode, use that; otherwise auto-detect
	if *connectionMode == "" {
		if cfg.SSHHost != "" {
			cfg.ConnectionMode = "ssh"
		} else {
			cfg.ConnectionMode = "local"
		}
	}

	if err := FinalizeSourceCmd(cfg); err != nil {
		return nil, err
	}

	// Handle positional arguments (interval [count])
	args := stripDebugFlagsFromArgs(flag.Args(), cfg)

	// Check if in direct execution mode (including metric mode with -f)
	isDirectMode := cfg.ExecuteScript != "" || cfg.ExecuteSQL != "" || cfg.ReadScript != "" ||
		cfg.CopyScript != "" || cfg.FindScriptSet

	// Handle interval and count from positional arguments
	// Positional args: [interval] [count]
	// - Monitor mode: ytop [interval] [count]
	// - Direct mode: ytop -f xxx [interval] [count]
	// - Metric mode: ytop -f xxx -m [interval] [count]

	intervalSpecified := false
	countSpecified := false

	if len(args) >= 1 {
		if i, err := strconv.Atoi(args[0]); err == nil && i >= 0 {
			cfg.Interval = i
			intervalSpecified = true
		}
	}

	if len(args) >= 2 {
		if c, err := strconv.Atoi(args[1]); err == nil && c >= 0 {
			cfg.Count = c
			countSpecified = true
		}
	}

	// In direct execution mode (-f/-q/-r/-c/-S), if neither interval nor count specified,
	// execute once (interval=0, count=1). If interval is specified but count is not,
	// count defaults to 0 (infinite loop), consistent with monitor mode.
	// This applies to all direct modes including metric mode (-f xxx -m).
	if isDirectMode {
		if !intervalSpecified {
			cfg.Interval = 0
			if !countSpecified {
				cfg.Count = 1
			}
		}
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// loadFromFile loads configuration from INI file
func loadFromFile(cfg *Config, path string) error {
	iniFile, err := ini.Load(path)
	if err != nil {
		return err
	}

	section := iniFile.Section("")

	if section.HasKey("connection_mode") {
		cfg.ConnectionMode = section.Key("connection_mode").String()
	}
	if section.HasKey("yasql_path") {
		cfg.YasqlPath = section.Key("yasql_path").String()
	}
	if section.HasKey("connect_string") {
		cfg.ConnectString = section.Key("connect_string").String()
	}
	if section.HasKey("ssh_host") {
		cfg.SSHHost = section.Key("ssh_host").String()
	}
	if section.HasKey("ssh_port") {
		cfg.SSHPort = section.Key("ssh_port").MustInt(22)
	}
	if section.HasKey("ssh_user") {
		cfg.SSHUser = section.Key("ssh_user").String()
	}
	if section.HasKey("ssh_password") {
		cfg.SSHPassword = section.Key("ssh_password").String()
	}
	if section.HasKey("ssh_key_file") {
		cfg.SSHKeyFile = section.Key("ssh_key_file").String()
	}
	if section.HasKey("source_cmd") {
		cfg.SourceCmd = section.Key("source_cmd").String()
	}
	if section.HasKey("interval") {
		cfg.Interval = section.Key("interval").MustInt(1)
	}
	if section.HasKey("count") {
		cfg.Count = section.Key("count").MustInt(0)
	}
	if section.HasKey("output_file") {
		cfg.OutputFile = section.Key("output_file").String()
	}
	if section.HasKey("session_top_n") {
		cfg.SessionTopN = section.Key("session_top_n").MustInt(10)
	}
	if section.HasKey("session_sort_by") {
		cfg.SessionSortBy = section.Key("session_sort_by").String()
	}
	if section.HasKey("session_detail_top_n") {
		cfg.SessionDetailTopN = section.Key("session_detail_top_n").MustInt(10)
	}
	if section.HasKey("sysstat_metrics") {
		metricsStr := section.Key("sysstat_metrics").String()
		if metricsStr != "" {
			cfg.SysStatMetrics = strings.Split(metricsStr, ",")
			for i := range cfg.SysStatMetrics {
				cfg.SysStatMetrics[i] = strings.TrimSpace(cfg.SysStatMetrics[i])
			}
		}
	}
	if section.HasKey("event_top_n") {
		cfg.EventTopN = section.Key("event_top_n").MustInt(5)
	}

	return nil
}

// stripDebugFlagsFromArgs removes -D/--debug from positional arguments.
// Standard Go flag parsing stops at the first non-flag argument, so a trailing
// "-D" after e.g. "ytop ... 3 -D" would otherwise be ignored; stripping here enables debug anyway.
func stripDebugFlagsFromArgs(args []string, cfg *Config) []string {
	var out []string
	for _, a := range args {
		if a == "-D" || a == "--debug" {
			cfg.DebugMode = true
			continue
		}
		out = append(out, a)
	}
	return out
}

// Validate checks if the configuration is valid
func (c *Config) Validate() error {
	if c.ConnectionMode != "local" && c.ConnectionMode != "ssh" {
		return fmt.Errorf("connection_mode must be 'local' or 'ssh'")
	}

	if c.ConnectionMode == "ssh" {
		if c.SSHHost == "" {
			return fmt.Errorf("ssh_host is required when connection_mode is 'ssh'")
		}

		// Check if ssh command exists
		if err := checkSSHCommand(); err != nil {
			return err
		}

		// Set default SSH user based on DB type if not specified
		if c.SSHUser == "" {
			switch c.DBType {
			case "oracle":
				c.SSHUser = "oracle"
			case "dameng":
				c.SSHUser = "dmdba"
			case "mysql":
				c.SSHUser = "root"
			case "postgresql":
				c.SSHUser = "postgres"
			default:
				c.SSHUser = "yashan"
			}
		}
		// If no password or key file specified, try default SSH key
		if c.SSHPassword == "" && c.SSHKeyFile == "" {
			homeDir, err := os.UserHomeDir()
			if err == nil {
				defaultKeyFile := homeDir + "/.ssh/id_rsa"
				if _, err := os.Stat(defaultKeyFile); err == nil {
					c.SSHKeyFile = defaultKeyFile
				} else {
					return fmt.Errorf("either ssh_password or ssh_key_file is required for SSH connection (default key ~/.ssh/id_rsa not found)")
				}
			} else {
				return fmt.Errorf("either ssh_password or ssh_key_file is required for SSH connection")
			}
		}
	}

	// In direct execution mode, interval can be 0
	// In interactive monitoring mode, interval must be at least 1
	isDirectMode := c.ExecuteScript != "" || c.ExecuteSQL != "" || c.ReadScript != "" ||
		c.CopyScript != "" || c.FindScriptSet

	if !isDirectMode && c.Interval < 1 {
		return fmt.Errorf("interval must be at least 1 second")
	}

	if c.Count < 0 {
		return fmt.Errorf("count cannot be negative")
	}

	return nil
}

// checkSSHCommand checks if ssh command is available
func checkSSHCommand() error {
	_, err := exec.LookPath("ssh")
	if err != nil {
		return fmt.Errorf("ssh command not found in PATH. Please install OpenSSH client to use SSH connection mode")
	}
	return nil
}

// PrintUsage prints brief usage with mode overview
func PrintUsage() {
	fmt.Println("ytop - Real-time database performance monitor")
	fmt.Println()
	fmt.Println("Modes:")
	fmt.Println("  ytop [options] [interval] [count]             Monitor (default)")
	fmt.Println("  ytop -f <script>|-q <sql> [options] [int] [n] Script execution")
	fmt.Println("  ytop stat|sesstat [options] [interval] [count] Session statistics")
	fmt.Println("  ytop event|sesevent [options] [interval] [count] Session events")
	fmt.Println("  ytop ssh [options]                          Configure SSH passwordless login")
	fmt.Println()
	fmt.Println("Use \"ytop <mode> --help\" for details:")
	fmt.Println("  ytop monitor --help      Monitor mode help")
	fmt.Println("  ytop script --help       Script execution help")
	fmt.Println("  ytop stat --help         Session statistics help")
	fmt.Println("  ytop event --help        Session events help")
	fmt.Println("  ytop ssh --help          SSH passwordless login help")
	fmt.Println()
	fmt.Println("Connection:")
	fmt.Println("  -C, --connect <str>       Connection string (default: / as sysdba)")
	fmt.Println("  -t, --host <host>         SSH host (enables SSH mode)")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -u, --user <user>         SSH user")
	fmt.Println("  -p, --password <pass>     SSH password")
	fmt.Println("  -k, --key <file>          SSH private key file")
	fmt.Println("  -s, --source <path>       Env file to source before DB CLI")
	fmt.Println("  --config <file>           Path to config file")
	fmt.Println()
	fmt.Println("Database:")
	fmt.Println("  -d, --db-type <type>      DB type: yas(han)(default), o(ra), d(m), m(y), p(g)")
	fmt.Println("  --login-cmd <cmd>         Custom DB login command")
	fmt.Println()
	fmt.Println("Output:")
	fmt.Println("  -o, --output <file>       Append output to file")
	fmt.Println("  -I, --inst <id>           Instance ID (0=all, default: 0)")
	fmt.Println("  -D, --debug               Enable debug mode")
	fmt.Println("  -v, --version             Show version")
}

// PrintMonitorUsage prints detailed help for monitor mode
func PrintMonitorUsage() {
	fmt.Println("ytop monitor - Real-time interactive monitoring (default mode)")
	fmt.Println()
	fmt.Println("Usage:  ytop [options] [interval] [count]")
	fmt.Println()
	fmt.Println("Displays live database metrics in terminal:")
	fmt.Println("  - System statistics (v$sysstat) per-second rates")
	fmt.Println("  - TOP 5 wait events (v$system_event)")
	fmt.Println("  - TOP N sessions by configurable column")
	fmt.Println("  - Active session details")
	fmt.Println()
	fmt.Println("Connection:")
	fmt.Println("  -C, --connect <str>       Connection string (default: / as sysdba)")
	fmt.Println("  -t, --host <host>         SSH host (enables SSH mode)")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -u, --user <user>         SSH user")
	fmt.Println("  -p, --password <pass>     SSH password")
	fmt.Println("  -k, --key <file>          SSH private key file")
	fmt.Println("  -s, --source <path>       Env file to source before DB CLI")
	fmt.Println("  --config <file>           Path to config file")
	fmt.Println()
	fmt.Println("Database:")
	fmt.Println("  -d, --db-type <type>      DB type: yas(han)(default), o(ra), d(m), m(y), p(g)")
	fmt.Println("  --login-cmd <cmd>         Custom DB login command")
	fmt.Println()
	fmt.Println("Output:")
	fmt.Println("  -o, --output <file>       Append output to file")
	fmt.Println("  --session-top <num>       TOP N sessions (default: 5)")
	fmt.Println("  --session-sort <col>      Session sort column (default: DB TIME)")
	fmt.Println("  --session-detail-top <n>  Active sessions to show (default: 10)")
	fmt.Println("  -I, --inst <id>           Instance ID (0=all, default: 0)")
	fmt.Println("  -D, --debug               Enable debug mode")
	fmt.Println()
	fmt.Println("Positional:  [interval] [count]  default: 5s, unlimited")
	fmt.Println()
	fmt.Println("Interactive Keys:")
	fmt.Println("  ↑/↓          Navigate sessions        a/A    Ad-hoc SQL")
	fmt.Println("  p/P          View SQL plan            s/S    Execute script/cmd")
	fmt.Println("  r/R          View script content      f/F    Search scripts")
	fmt.Println("  c/C          Copy script              h/H    Show help")
	fmt.Println("  q/Q/ESC      Quit")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  ytop                                        # Default: 5s interval, unlimited")
	fmt.Println("  ytop 1                                      # 1s interval, unlimited")
	fmt.Println("  ytop 1 20                                   # 1s interval, 20 iterations")
	fmt.Println("  ytop -C \"/ as sysdba\"                       # Local connection")
	fmt.Println("  ytop -t 10.10.10.130 -u yashan -p oracle -s ~/.bashrc")
	fmt.Println("  ytop --config config.ini                    # Use config file")
	fmt.Println("  ytop --session-top 20 --session-sort \"CPU TIME\"")
}

// PrintScriptUsage prints detailed help for script execution mode
func PrintScriptUsage() {
	fmt.Println("ytop script - Execute scripts and SQL queries")
	fmt.Println()
	fmt.Println("Usage:  ytop -f <script>|-q <sql> [options] [interval] [count]")
	fmt.Println()
	fmt.Println("Execution:")
	fmt.Println("  -f <script>               Execute script (SQL or OS)")
	fmt.Println("                             SQL scripts: search in embedded sql/ directory")
	fmt.Println("                             OS scripts: search in embedded os/ directory")
	fmt.Println("                             Full path: /path/to/script.sql or ./script.sql")
	fmt.Println("  -q <sql>                  Execute SQL query directly")
	fmt.Println("  -r <script>               View script content")
	fmt.Println("  --copy <script> [dest]    Copy script to destination (default: /tmp)")
	fmt.Println("  -S <pattern>              Search scripts by regex (empty pattern lists all)")
	fmt.Println("  -m, --metric              Delta/per-second mode (with -f)")
	fmt.Println()
	fmt.Println("Connection:")
	fmt.Println("  -C, --connect <str>       Connection string (default: / as sysdba)")
	fmt.Println("  -t, --host <host>         SSH host (enables SSH mode)")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -u, --user <user>         SSH user")
	fmt.Println("  -p, --password <pass>     SSH password")
	fmt.Println("  -k, --key <file>          SSH private key file")
	fmt.Println("  -s, --source <path>       Env file to source before DB CLI")
	fmt.Println("  --config <file>           Path to config file")
	fmt.Println()
	fmt.Println("Database:")
	fmt.Println("  -d, --db-type <type>      DB type: yas(han)(default), o(ra), d(m), m(y), p(g)")
	fmt.Println("  --login-cmd <cmd>         Custom DB login command")
	fmt.Println()
	fmt.Println("Output:")
	fmt.Println("  -o, --output <file>       Append output to file")
	fmt.Println("  -I, --inst <id>           Instance ID (0=all, default: 0)")
	fmt.Println("  -D, --debug               Enable debug mode")
	fmt.Println()
	fmt.Println("Positional:  [interval] [count]")
	fmt.Println("  Default without interval: execute once")
	fmt.Println("  With interval: repeat every N seconds, unlimited or count times")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  ytop -f we.sql                              # Execute SQL script once")
	fmt.Println("  ytop -f we.sql 5 10                         # Every 5s, 10 times")
	fmt.Println("  ytop -f gv_vm.sql -m 1 10                   # Metric mode, 1s, 10 times")
	fmt.Println("  ytop -q \"select * from v$version\"            # Execute SQL query once")
	fmt.Println("  ytop -q \"select count(*) from v$session\" 2 5 # Query every 2s, 5 times")
	fmt.Println("  ytop -t 10.10.10.130 -f iostat.sh           # Execute OS script on remote")
	fmt.Println("  ytop -r we.sql                              # View script content")
	fmt.Println("  ytop --copy 'we.sql /tmp'                   # Copy script")
	fmt.Println("  ytop -S 'awr'                               # Search scripts")
	fmt.Println("  ytop -S                                     # List all scripts (same as -S '.*')")
	fmt.Println("  ytop -d o --login-cmd 'sqlplus / as sysdba' -f we.sql")
	fmt.Println("  ytop -d m --login-cmd 'mysql -uroot -p\"pass\" mydb' -f we.sql")
}

// PrintSesstatUsage prints detailed help for sesstat subcommand
func PrintSesstatUsage() {
	fmt.Println("ytop sesstat - Query session statistics (v$sesstat)")
	fmt.Println()
	fmt.Println("Usage:  ytop stat [options] [interval] [count]")
	fmt.Println()
	fmt.Println("Stat Options:")
	fmt.Println("  -S, --sid <sids>          Session ID filter (comma-separated, e.g. 40,50,90)")
	fmt.Println("  -n, --stat <names>        Stat name filter (comma-separated, supports % wildcard)")
	fmt.Println()
	fmt.Println("Connection:")
	fmt.Println("  -C, --connect <str>       Connection string (default: / as sysdba)")
	fmt.Println("  -t, --host <host>         SSH host (enables SSH mode)")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -u, --user <user>         SSH user")
	fmt.Println("  -p, --password <pass>     SSH password")
	fmt.Println("  -k, --key <file>          SSH private key file")
	fmt.Println("  -s, --source <path>       Env file to source before DB CLI")
	fmt.Println()
	fmt.Println("Output:")
	fmt.Println("  --session-top <num>       TOP N results (default: 5)")
	fmt.Println("  -I, --inst <id>           Instance ID (0=all, default: 0)")
	fmt.Println("  -D, --debug               Enable debug mode")
	fmt.Println()
	fmt.Println("Positional:  [interval] [count]  default: 1s, 2")
	fmt.Println()
	fmt.Println("Behavior:")
	fmt.Println("  Without --sid: TOP N sessions by total stat value")
	fmt.Println("  With --sid:    TOP N stats for specified sessions")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  ytop stat -t 10.10.10.130 -u yashan -p oracle -s ~/.bashrc")
	fmt.Println("  ytop stat -S 40,50 -n \"CPU%,parse%\"")
	fmt.Println("  ytop stat -I 1 --session-top 10")
}

// PrintSeseventUsage prints detailed help for sesevent subcommand
func PrintSeseventUsage() {
	fmt.Println("ytop sesevent - Query session events (v$session_event)")
	fmt.Println()
	fmt.Println("Usage:  ytop event [options] [interval] [count]")
	fmt.Println()
	fmt.Println("Event Options:")
	fmt.Println("  -S, --sid <sids>          Session ID filter (comma-separated, e.g. 40,50,90)")
	fmt.Println("  -e, --event <names>       Event name filter (comma-separated, supports % wildcard)")
	fmt.Println()
	fmt.Println("Connection:")
	fmt.Println("  -C, --connect <str>       Connection string (default: / as sysdba)")
	fmt.Println("  -t, --host <host>         SSH host (enables SSH mode)")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -u, --user <user>         SSH user")
	fmt.Println("  -p, --password <pass>     SSH password")
	fmt.Println("  -k, --key <file>          SSH private key file")
	fmt.Println("  -s, --source <path>       Env file to source before DB CLI")
	fmt.Println()
	fmt.Println("Output:")
	fmt.Println("  --session-top <num>       TOP N results (default: 5)")
	fmt.Println("  -I, --inst <id>           Instance ID (0=all, default: 0)")
	fmt.Println("  -D, --debug               Enable debug mode")
	fmt.Println()
	fmt.Println("Positional:  [interval] [count]  default: 1s, 2")
	fmt.Println()
	fmt.Println("Behavior:")
	fmt.Println("  Without --sid: TOP N sessions by total wait time")
	fmt.Println("  With --sid:    TOP N events for specified sessions")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  ytop event -t 10.10.10.130 -u yashan -p oracle -s ~/.bashrc")
	fmt.Println("  ytop event -S 40,50 -e \"db%,log%\"")
	fmt.Println("  ytop event -I 1 --session-top 10")
}

// PrintSSHUsage prints detailed help for the ssh subcommand
func PrintSSHUsage() {
	fmt.Println("ytop ssh - Configure SSH passwordless login")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  ytop ssh -t <host> -u <user> -p <password> [options]       Setup")
	fmt.Println("  ytop ssh --delete -t <host> -u <user> [-k <key>]           Remove")
	fmt.Println()
	fmt.Println("Setup:  automate SSH key-based authentication (equivalent to ssh-copy-id).")
	fmt.Println("Delete: remove public key from remote host (uses key auth, no password needed).")
	fmt.Println()
	fmt.Println("Required:")
	fmt.Println("  -t, --host <host>         Target SSH host")
	fmt.Println("  -u, --user <user>         SSH username")
	fmt.Println("  -p, --password <pass>     SSH password (required for setup only)")
	fmt.Println()
	fmt.Println("Options:")
	fmt.Println("  -P, --port <port>         SSH port (default: 22)")
	fmt.Println("  -k, --key <file>          Local private key file (default: ~/.ssh/id_rsa)")
	fmt.Println("  --delete                  Remove public key from remote host")
	fmt.Println()
	fmt.Println("Examples:")
	fmt.Println("  ytop ssh -t 10.10.10.130 -u yashan -p 'mypassword'")
	fmt.Println("  ytop ssh -t 10.10.10.130 -u yashan -p 'pass' -P 2222")
	fmt.Println("  ytop ssh --delete -t 10.10.10.130 -u yashan")
	fmt.Println("  ytop ssh --delete -t 10.10.10.130 -u yashan -k ~/.ssh/id_rsa")
}
