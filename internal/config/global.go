package config

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// GlobalFlags holds shared command-line flags for subcommands (stat/event/ssh).
type GlobalFlags struct {
	ConfigFile     string
	ConnectionMode string
	YasqlPath      string
	ConnectString  string
	SSHHost        string
	SSHPort        int
	SSHUser        string
	SSHPassword    string
	SSHKeyFile     string
	SourceCmd      string

	DBType    string
	DBVersion string
	LoginCmd  string
	TargetOS  string

	Interval int
	Count    int
	TopN     int

	OutputFile string
	InstanceID int
	NoColor    bool
	Debug      bool
}

// ParseGlobalFlags registers shared flags on fs and returns the struct to fill.
func ParseGlobalFlags(fs *flag.FlagSet) *GlobalFlags {
	gf := &GlobalFlags{}

	fs.StringVar(&gf.ConfigFile, "config", "", "Path to config file")
	fs.StringVar(&gf.ConfigFile, "c", "", "Path to config file (short)")

	fs.StringVar(&gf.ConnectionMode, "mode", "", "Connection mode: local or ssh")

	fs.StringVar(&gf.YasqlPath, "yasql", "", "Path to yasql executable")

	fs.StringVar(&gf.ConnectString, "connect", "", "Connection string")
	fs.StringVar(&gf.ConnectString, "C", "", "Connection string (short)")

	fs.StringVar(&gf.SSHHost, "host", "", "SSH host")
	fs.StringVar(&gf.SSHHost, "t", "", "SSH host (short)")

	fs.IntVar(&gf.SSHPort, "port", 0, "SSH port")
	fs.IntVar(&gf.SSHPort, "P", 0, "SSH port (short)")

	fs.StringVar(&gf.SSHUser, "user", "", "SSH user")
	fs.StringVar(&gf.SSHUser, "u", "", "SSH user (short)")

	fs.StringVar(&gf.SSHPassword, "password", "", "SSH password")
	fs.StringVar(&gf.SSHPassword, "p", "", "SSH password (short)")

	fs.StringVar(&gf.SSHKeyFile, "key", "", "SSH private key file")
	fs.StringVar(&gf.SSHKeyFile, "k", "", "SSH private key file (short)")

	fs.StringVar(&gf.SourceCmd, "source", "", "Source command to run before yasql")
	fs.StringVar(&gf.SourceCmd, "s", "", "Source command (short)")

	fs.StringVar(&gf.DBType, "db-type", "", "Database type (long form)")
	fs.StringVar(&gf.DBType, "d", "", "Database type (short)")

	fs.StringVar(&gf.DBVersion, "db-version", "", "Database version for script resolution")
	fs.StringVar(&gf.DBVersion, "V", "", "Database version (short)")

	fs.StringVar(&gf.LoginCmd, "login-cmd", "", "Custom DB login command")
	fs.StringVar(&gf.TargetOS, "target-os", "", "Remote OS: windows or unix")

	fs.IntVar(&gf.Interval, "interval", 0, "Interval in seconds")
	fs.IntVar(&gf.Interval, "i", 0, "Interval (short)")

	fs.IntVar(&gf.Count, "count", -1, "Number of result outputs (-1 = not set)")

	fs.IntVar(&gf.TopN, "top", 0, "Number of top results to show")
	fs.IntVar(&gf.TopN, "T", 0, "Number of top results (short)")
	fs.IntVar(&gf.TopN, "session-top", 0, "TOP N sessions (alias)")

	fs.StringVar(&gf.OutputFile, "output", "", "Output file path")
	fs.StringVar(&gf.OutputFile, "o", "", "Output file (short)")

	fs.IntVar(&gf.InstanceID, "inst", -1, "Instance ID (-1 = not set)")
	fs.IntVar(&gf.InstanceID, "I", -1, "Instance ID (short)")
	fs.IntVar(&gf.InstanceID, "inst-id", -1, "Instance ID (alias)")

	fs.BoolVar(&gf.NoColor, "no-color", false, "Disable color output")
	fs.BoolVar(&gf.Debug, "debug", false, "Enable debug mode")
	fs.BoolVar(&gf.Debug, "D", false, "Enable debug mode (short)")

	return gf
}

// ApplyToConfig merges global flags into cfg. When visited is non-nil, only flags
// the user passed on the command line are applied (INI values are preserved).
func (gf *GlobalFlags) ApplyToConfig(cfg *Config, visited map[string]bool) error {
	if VisitedAny(visited, "mode") && gf.ConnectionMode != "" {
		cfg.ConnectionMode = gf.ConnectionMode
	} else if VisitedAny(visited, "t", "host") && gf.SSHHost != "" {
		cfg.ConnectionMode = "ssh"
	} else if VisitedAny(visited, "t", "host") && gf.SSHHost == "" && cfg.SSHHost == "" {
		cfg.ConnectionMode = "local"
	}

	if VisitedAny(visited, "yasql") && gf.YasqlPath != "" {
		cfg.YasqlPath = gf.YasqlPath
	}
	if VisitedAny(visited, "connect", "C") && gf.ConnectString != "" {
		cfg.ConnectString = gf.ConnectString
	}
	if VisitedAny(visited, "t", "host") && gf.SSHHost != "" {
		cfg.SSHHost = gf.SSHHost
	}
	if VisitedAny(visited, "port", "P") && gf.SSHPort != 0 {
		cfg.SSHPort = gf.SSHPort
	}
	if VisitedAny(visited, "user", "u") && gf.SSHUser != "" {
		cfg.SSHUser = gf.SSHUser
	}
	if VisitedAny(visited, "password", "p") && gf.SSHPassword != "" {
		cfg.SSHPassword = gf.SSHPassword
	}
	if VisitedAny(visited, "key", "k") && gf.SSHKeyFile != "" {
		cfg.SSHKeyFile = gf.SSHKeyFile
	}
	if VisitedAny(visited, "source", "s") && gf.SourceCmd != "" {
		cfg.SourceCmd = gf.SourceCmd
	}

	if VisitedAny(visited, "db-type", "d") && gf.DBType != "" {
		parsed, err := parseDBType(gf.DBType)
		if err != nil {
			return err
		}
		cfg.DBType = parsed
	}
	if VisitedAny(visited, "db-version", "V") && gf.DBVersion != "" {
		cfg.DBVersion = gf.DBVersion
	}
	if VisitedAny(visited, "login-cmd") && gf.LoginCmd != "" {
		cfg.LoginCmd = gf.LoginCmd
	}
	if VisitedAny(visited, "target-os") && gf.TargetOS != "" {
		osName, err := parseTargetOS(gf.TargetOS)
		if err != nil {
			return err
		}
		cfg.TargetOS = osName
	}

	if VisitedAny(visited, "interval", "i") && gf.Interval > 0 {
		cfg.Interval = gf.Interval
	}
	if VisitedAny(visited, "count") && gf.Count >= 0 {
		cfg.Count = gf.Count
	}
	if VisitedAny(visited, "top", "T", "session-top") && gf.TopN > 0 {
		cfg.SessionTopN = gf.TopN
	}
	if VisitedAny(visited, "output", "o") && gf.OutputFile != "" {
		cfg.OutputFile = gf.OutputFile
	}
	if VisitedAny(visited, "inst", "I", "inst-id") && gf.InstanceID >= 0 {
		cfg.InstanceID = gf.InstanceID
	}
	if VisitedAny(visited, "no-color") && gf.NoColor {
		cfg.ColorEnabled = false
	}
	if VisitedAny(visited, "debug", "D") && gf.Debug {
		cfg.DebugMode = true
	}

	if cfg.ConnectionMode == "" {
		if cfg.SSHHost != "" {
			cfg.ConnectionMode = "ssh"
		} else {
			cfg.ConnectionMode = "local"
		}
	} else if !cfg.iniConnectionModeSet && cfg.ConnectionMode == "local" && cfg.SSHHost != "" {
		cfg.ConnectionMode = "ssh"
	}

	cfg.ApplyDBTypeConnectDefaults()
	return nil
}

// SubcommandTiming resolves interval/count/topN for stat/event: CLI > INI > defaults (1s, 2, top 5).
func SubcommandTiming(cfg *Config, gf *GlobalFlags, visited map[string]bool) (interval, count, topN int) {
	interval = 1
	count = 2
	topN = 5

	if cfg.iniIntervalSet {
		interval = cfg.Interval
	}
	if cfg.iniCountSet {
		count = cfg.Count
	}
	if cfg.iniSessionTopSet {
		topN = cfg.SessionTopN
	}

	if VisitedAny(visited, "interval", "i") && gf.Interval > 0 {
		interval = gf.Interval
	}
	if VisitedAny(visited, "count") && gf.Count >= 0 {
		count = gf.Count
	}
	if VisitedAny(visited, "top", "T", "session-top") && gf.TopN > 0 {
		topN = gf.TopN
	}
	return interval, count, topN
}

// LoadSubcommandConfig loads INI then applies global CLI flags for stat/event/ssh entry points.
func LoadSubcommandConfig(gf *GlobalFlags, fs *flag.FlagSet, entry string) (*Config, error) {
	cfg := DefaultConfig()
	resetLoadTrace(entry)
	visited := make(map[string]bool)
	if fs != nil {
		fs.Visit(func(f *flag.Flag) {
			visited[f.Name] = true
		})
	}
	recordCLIOverrides(visited)
	if err := LoadINIInto(cfg, resolveExplicitConfigPath(visited, gf.ConfigFile)); err != nil {
		return nil, err
	}
	if err := gf.ApplyToConfig(cfg, visited); err != nil {
		return nil, err
	}
	return cfg, nil
}

const winUserProfileVar = "%USERPROFILE%"

// FinalizeSourceCmd normalizes -s / source_cmd for a single env file path (no spaces).
// Non-absolute paths are under the login user's $HOME (SSH Unix) or %USERPROFILE% (SSH/local Windows).
// If the user omitted quotes and the shell expanded ~ to the local home directory, the path
// is rewritten to $HOME/... on Unix or %USERPROFILE%\... on Windows.
// Custom shell snippets (contain spaces, or start with "source ") are left unchanged.
// For local simple paths, the file must exist (os.Stat). For SSH, the caller should run
// SSHSourceExistenceCheck on the remote during Connect.
func FinalizeSourceCmd(cfg *Config) error {
	cfg.SSHSourceExistenceCheck = ""
	if cfg.SourceCmd == "" {
		return nil
	}
	raw := strings.TrimSpace(cfg.SourceCmd)
	// Full shell command: do not interpret as a bare file path
	if strings.Contains(raw, " ") || strings.HasPrefix(raw, "source ") {
		return nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("user home directory: %w", err)
	}
	homeSlash := filepath.ToSlash(home)

	if cfg.ConnectionMode == "ssh" {
		resolved := normalizeSSHSourcePath(raw, homeSlash, cfg.TargetOS)
		cfg.SourceCmd = resolved
		cfg.SSHSourceExistenceCheck = resolved
		return nil
	}

	if isWindowsTarget(cfg) {
		resolved, err := normalizeWindowsLocalSourcePath(raw, home)
		if err != nil {
			return err
		}
		if _, err := os.Stat(resolved); err != nil {
			return fmt.Errorf("source file not found: %s: %w", resolved, err)
		}
		cfg.SourceCmd = resolved
		return nil
	}

	resolved, err := normalizeLocalSourcePath(raw, home)
	if err != nil {
		return err
	}
	if _, err := os.Stat(resolved); err != nil {
		return fmt.Errorf("source file not found: %s: %w", resolved, err)
	}
	cfg.SourceCmd = formatLocalSource(resolved)
	return nil
}

// AdaptSourceCmdForWindowsSSH rewrites Unix-style -s paths after SSH target OS is detected as Windows.
// Converts $HOME/... to %USERPROFILE%\... and forward slashes to backslashes.
func AdaptSourceCmdForWindowsSSH(cfg *Config) {
	if cfg == nil || cfg.SourceCmd == "" || cfg.TargetOS != "windows" {
		return
	}
	raw := strings.TrimSpace(cfg.SourceCmd)
	if strings.Contains(raw, " ") || strings.HasPrefix(raw, "source ") {
		return
	}
	adapted := toWindowsRemoteSourcePath(raw)
	cfg.SourceCmd = adapted
	cfg.SSHSourceExistenceCheck = adapted
}

func isWindowsTarget(cfg *Config) bool {
	if cfg.TargetOS == "windows" {
		return true
	}
	return cfg.ConnectionMode == "local" && isLocalWindows()
}

func normalizeLocalSourcePath(path, home string) (string, error) {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	if strings.HasPrefix(path, "~/") {
		return filepath.Clean(filepath.Join(home, path[2:])), nil
	}
	if filepath.IsAbs(path) {
		return filepath.Clean(path), nil
	}
	path = strings.TrimPrefix(path, "./")
	return filepath.Clean(filepath.Join(home, path)), nil
}

func normalizeWindowsLocalSourcePath(path, home string) (string, error) {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	if path == "~" {
		return home, nil
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Clean(filepath.Join(home, path[2:])), nil
	}
	if isWindowsDrivePath(path) {
		return toWindowsNativePath(path), nil
	}
	if filepath.IsAbs(path) {
		return toWindowsNativePath(path), nil
	}
	path = strings.TrimPrefix(path, "./")
	return filepath.Clean(filepath.Join(home, path)), nil
}

func normalizeSSHSourcePath(path, homeSlash, targetOS string) string {
	if targetOS == "windows" {
		return normalizeWindowsSSHSourcePath(path, homeSlash)
	}
	return normalizeUnixSSHSourcePath(path, homeSlash)
}

func normalizeUnixSSHSourcePath(path, homeSlash string) string {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	// Local shell expanded ~ to the control machine's home; map to remote $HOME
	if homeSlash != "" {
		if path == homeSlash {
			return "$HOME"
		}
		prefix := homeSlash + "/"
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			if rest == "" {
				return "$HOME"
			}
			return "$HOME/" + rest
		}
	}
	if path == "~" {
		return "$HOME"
	}
	if strings.HasPrefix(path, "~/") {
		rest := strings.TrimPrefix(path, "~/")
		if rest == "" {
			return "$HOME"
		}
		return "$HOME/" + rest
	}
	if isWindowsDrivePath(path) {
		return path
	}
	if strings.HasPrefix(path, "/") {
		return path
	}
	path = strings.TrimPrefix(path, "./")
	if path == "" || path == "." {
		return "$HOME"
	}
	return "$HOME/" + path
}

func normalizeWindowsSSHSourcePath(path, homeSlash string) string {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	// Control machine shell expanded ~ to local home; map to remote %USERPROFILE%
	if homeSlash != "" {
		if path == homeSlash {
			return winUserProfileVar
		}
		prefix := homeSlash + "/"
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			return joinWindowsRemoteProfile(rest)
		}
	}
	if path == "~" {
		return winUserProfileVar
	}
	if strings.HasPrefix(path, "~/") {
		rest := strings.TrimPrefix(path, "~/")
		return joinWindowsRemoteProfile(rest)
	}
	if isWindowsDrivePath(path) {
		return toWindowsNativePath(path)
	}
	if strings.HasPrefix(path, "/") {
		return toWindowsNativePath(path)
	}
	path = strings.TrimPrefix(path, "./")
	if path == "" || path == "." {
		return winUserProfileVar
	}
	return joinWindowsRemoteProfile(path)
}

func toWindowsRemoteSourcePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "$HOME" {
		return winUserProfileVar
	}
	if strings.HasPrefix(path, "$HOME/") {
		return joinWindowsRemoteProfile(strings.TrimPrefix(path, "$HOME/"))
	}
	if strings.Contains(path, "/") {
		return toWindowsNativePath(path)
	}
	return path
}

func joinWindowsRemoteProfile(rest string) string {
	rest = strings.TrimSpace(rest)
	rest = strings.TrimPrefix(rest, "./")
	if rest == "" || rest == "." {
		return winUserProfileVar
	}
	return winUserProfileVar + "\\" + strings.ReplaceAll(rest, "/", "\\")
}

func toWindowsNativePath(path string) string {
	return strings.ReplaceAll(path, "/", "\\")
}

func isWindowsDrivePath(path string) bool {
	return len(path) >= 2 && path[1] == ':'
}

func formatLocalSource(resolved string) string {
	return "source " + shellSingleQuote(filepath.ToSlash(resolved))
}

func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}
