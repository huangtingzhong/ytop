package connector

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
)

// LocalConnector implements Connector for local DB CLI execution.
type LocalConnector struct {
	cfg       *config.Config
	connected bool
}

// NewLocalConnector creates a new local connector.
func NewLocalConnector(cfg *config.Config) *LocalConnector {
	return &LocalConnector{cfg: cfg}
}

// Connect verifies the DB CLI is available on the local machine.
func (c *LocalConnector) Connect(ctx context.Context) error {
	localOS := platform.LocalOS()

	// Propagate local OS to cfg.TargetOS so executor/ssh can use it.
	if c.cfg.TargetOS == "" {
		c.cfg.TargetOS = localOS
	}

	logger.DebugStep("local-connect", fmt.Sprintf("DB=%s OS=%s mode=local", c.cfg.DBType, localOS))
	logger.DebugKeyVal("DBType", c.cfg.DBType)
	logger.DebugKeyVal("ConnectString", c.cfg.ConnectString)
	logger.DebugKeyVal("LoginCmd", c.cfg.LoginCmd)
	logger.DebugKeyVal("SourceCmd", c.cfg.SourceCmd)
	logger.DebugKeyVal("LocalOS", localOS)

	// LoginCmd overrides CLI resolution — assume the user's command is valid.
	if c.cfg.LoginCmd != "" {
		logger.Debug("[local-connect] login-cmd provided; skipping CLI check: %s\n", c.cfg.LoginCmd)
		c.connected = true
		return nil
	}

	// Resolve CLI: current PATH first, then after -s (aligned with SSH Connect).
	cliPath, err := platform.ResolveLocalCLI(ctx, c.cfg.DBType, c.cfg.YasqlPath, c.cfg.SourceCmd)
	if err != nil {
		hint := buildCLIHint(c.cfg.DBType, localOS, c.cfg.SourceCmd)
		logger.DebugStep("local-connect FAILED", err.Error())
		return fmt.Errorf(
			"DB CLI '%s' not found or not executable.\n%s\n%s",
			platform.DefaultCLINameForDB(c.cfg.DBType, c.cfg.YasqlPath),
			err.Error(),
			hint,
		)
	}

	c.cfg.RemoteCLIPath = cliPath
	logger.Debug("[local-connect] CLI resolved: %s\n", cliPath)

	if c.cfg.SourceCmd != "" {
		if err := verifyLocalSourceCmd(ctx, localOS, c.cfg.SourceCmd); err != nil {
			logger.DebugStep("local-connect WARN", "source-cmd: "+err.Error())
			logger.Debug("[local-connect] WARN: %v\n", err)
		}
	}

	c.connected = true
	logger.DebugStep("local-connect OK", "")
	return nil
}

// buildSQLCmd builds the exec.Cmd to run SQL via the DB CLI or a custom login command.
func (c *LocalConnector) buildSQLCmd(ctx context.Context, sql string) *exec.Cmd {
	sql = WrapSQLSuppressScriptEcho(c.cfg.DBType, sql)
	sql = EnsureSQLStatementTerminator(sql, c.cfg.DBType)
	return BuildLocalSQLExecCmd(ctx, c.cfg, sql, "")
}

// ExecuteQuery executes a SQL query via the DB CLI.
func (c *LocalConnector) ExecuteQuery(ctx context.Context, sql string) ([][]string, error) {
	if !c.connected {
		return nil, fmt.Errorf("not connected")
	}
	cmd := c.buildSQLCmd(ctx, sql)
	if c.cfg.DebugMode {
		logger.DebugSection("local-query")
		logger.Debug("[local] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))
		logger.Debug("[local] Command: %v\n", cmd.Args)
	}
	output, err := cmd.CombinedOutput()
	if c.cfg.DebugMode {
		logger.DebugCommandOutput("local-query", string(output), err)
	}
	if err != nil {
		return nil, fmt.Errorf("SQL execution failed: %w\nOutput: %s", err, string(output))
	}
	rows, parseErr := parseYasqlOutput(string(output))
	if c.cfg.DebugMode {
		logger.Debug("[local] Parsed %d rows\n", len(rows))
	}
	return rows, parseErr
}

// ExecuteQueryWithHeader executes a SQL query and returns header + data rows.
func (c *LocalConnector) ExecuteQueryWithHeader(ctx context.Context, sql string) (header []string, rows [][]string, err error) {
	if !c.connected {
		return nil, nil, fmt.Errorf("not connected")
	}
	cmd := c.buildSQLCmd(ctx, sql)
	if c.cfg.DebugMode {
		logger.DebugSection("local-query-with-header")
		logger.Debug("[local] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))
		logger.Debug("[local] Command: %v\n", cmd.Args)
	}
	output, err := cmd.CombinedOutput()
	if c.cfg.DebugMode {
		logger.DebugCommandOutput("local-query-header", string(output), err)
	}
	if err != nil {
		return nil, nil, fmt.Errorf("SQL execution failed: %w\nOutput: %s", err, string(output))
	}
	return ParseYasqlOutputWithHeader(string(output))
}

// Close closes the connection.
func (c *LocalConnector) Close() error {
	c.connected = false
	return nil
}

// IsConnected returns connection status.
func (c *LocalConnector) IsConnected() bool {
	return c.connected
}

// buildCLIHint returns OS-specific troubleshooting hints for CLI resolution failures.
func buildCLIHint(dbType, localOS, sourceCmd string) string {
	var sb strings.Builder
	if localOS == platform.OSWindows {
		sb.WriteString("Hint (Windows):\n")
		sb.WriteString("  1. Add the DB client bin directory to the system PATH.\n")
		sb.WriteString(fmt.Sprintf("  2. Or use --login-cmd to specify the full path, e.g.:\n"))
		switch dbType {
		case "mysql":
			sb.WriteString(`     --login-cmd "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe -uroot -p"` + "\n")
		case "oracle":
			sb.WriteString(`     --login-cmd "C:\app\oracle\product\19.0\client\bin\sqlplus.exe / as sysdba"` + "\n")
		case "postgresql":
			sb.WriteString(`     --login-cmd "C:\Program Files\PostgreSQL\16\bin\psql.exe -U postgres"` + "\n")
		case "dameng":
			sb.WriteString(`     --login-cmd "C:\dmdbms\bin\disql.exe SYSDBA/SYSDBA"` + "\n")
		case "mssql":
			sb.WriteString(`     --login-cmd "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe -S localhost -U sa"` + "\n")
			sb.WriteString("  3. On SSH to Windows, ytop also tries SQL Server registry keys to locate sqlcmd when it is not in PATH.\n")
		}
		if sourceCmd != "" {
			sb.WriteString("  3. If the CLI is installed but needs env setup, check the -s bat file path.\n")
		}
	} else {
		sb.WriteString("Hint (Unix):\n")
		sb.WriteString("  1. Ensure the DB client is installed and in PATH.\n")
		if sourceCmd != "" {
			sb.WriteString(fmt.Sprintf("  2. Check that the -s env file exists: %s\n", sourceCmd))
		} else {
			sb.WriteString("  2. Use -s to source an env file that adds the CLI to PATH.\n")
		}
		sb.WriteString("  3. Or use --login-cmd to specify the full CLI invocation.\n")
	}
	return sb.String()
}

func verifyLocalSourceCmd(ctx context.Context, localOS, sourceCmd string) error {
	checkCmd := platform.SourceEnvFileCheckCmd(localOS, sourceCmd)
	var testCmd *exec.Cmd
	if localOS == platform.OSWindows {
		testCmd = exec.CommandContext(ctx, "cmd", "/C", checkCmd)
	} else {
		testCmd = exec.CommandContext(ctx, "bash", "-c", checkCmd)
	}
	if err := testCmd.Run(); err != nil {
		return fmt.Errorf("source file not found: %s", sourceEnvFileDisplay(sourceCmd))
	}
	return nil
}

func sourceEnvFileDisplay(sourceCmd string) string {
	s := strings.TrimSpace(sourceCmd)
	if strings.HasPrefix(s, "source ") {
		return strings.Trim(s[len("source "):], `"'`)
	}
	return s
}

// WrapSourceCmd prefixes cmd with SourceCmd (-s) when set.
func WrapSourceCmd(sourceCmd, cmd string) string {
	if sourceCmd != "" {
		return sourceCmd + " && " + cmd
	}
	return cmd
}

// FormatCLIInvocation builds a shell-safe CLI invocation string for bash -c.
func FormatCLIInvocation(cli string, args ...string) string {
	parts := make([]string, 0, 1+len(args))
	parts = append(parts, platform.ShellQuoteUnix(cli))
	for _, a := range args {
		parts = append(parts, platform.ShellQuoteUnix(a))
	}
	return strings.Join(parts, " ")
}

// MySQLDefaultClientArgs are always passed to the mysql CLI (table output for aligned columns).
var MySQLDefaultClientArgs = []string{"-t"}

// MySQLConnectArgs splits ConnectString into separate mysql client flags.
// Duplicate -t/-tt from ConnectString are dropped; ytop always supplies table output via MySQLDefaultClientArgs.
func MySQLConnectArgs(connectString string) []string {
	args := strings.Fields(strings.TrimSpace(connectString))
	out := make([]string, 0, len(args))
	for _, a := range args {
		if a == "-t" || a == "-tt" {
			continue
		}
		out = append(out, a)
	}
	return out
}

// FormatMySQLAdHocRemoteCmd builds mysql -e for remote SSH execution.
// Unix uses bash single-quote quoting; Windows uses cmd-friendly double-quote rules.
func FormatMySQLAdHocRemoteCmd(targetOS, cli, connectString, sql string) string {
	if targetOS == platform.OSWindows {
		return formatMySQLWindowsAdHoc(cli, connectString, sql)
	}
	return FormatMySQLCLIInvocation(cli, connectString, "-e", sql)
}

func formatMySQLWindowsAdHoc(cli, connectString, sql string) string {
	parts := append([]string{cli}, MySQLExecArgv(connectString, "-e", sql)...)
	quoted := make([]string, len(parts))
	for i, p := range parts {
		if strings.ContainsAny(p, " \t\"") {
			quoted[i] = `"` + strings.ReplaceAll(p, `"`, `""`) + `"`
		} else {
			quoted[i] = p
		}
	}
	return strings.Join(quoted, " ")
}

// FormatMySQLCLIInvocation builds a shell-safe mysql command with split connect flags.
func FormatMySQLCLIInvocation(cli, connectString string, extra ...string) string {
	parts := make([]string, 0, 2+len(extra)+4)
	parts = append(parts, cli)
	parts = append(parts, MySQLDefaultClientArgs...)
	parts = append(parts, MySQLConnectArgs(connectString)...)
	parts = append(parts, extra...)
	quoted := make([]string, len(parts))
	for i, p := range parts {
		quoted[i] = platform.ShellQuoteUnix(p)
	}
	return strings.Join(quoted, " ")
}

// FormatMySQLScriptRedirect builds: mysql [flags...] < 'script.sql' (Unix/bash).
func FormatMySQLScriptRedirect(cli, connectString, scriptFile string) string {
	return FormatMySQLScriptRedirectForOS(platform.OSUnix, cli, connectString, scriptFile)
}

// FormatMySQLScriptRedirectForOS builds a mysql script redirect for the target OS shell.
func FormatMySQLScriptRedirectForOS(targetOS, cli, connectString, scriptFile string) string {
	if targetOS == platform.OSWindows {
		return formatMySQLWindowsRedirect(cli, connectString, scriptFile)
	}
	return FormatMySQLCLIInvocation(cli, connectString) + " < " + platform.ShellQuoteUnix(scriptFile)
}

func formatMySQLWindowsRedirect(cli, connectString, scriptFile string) string {
	// Avoid cmd /C "mysql ... < file" — stdin redirect inside quoted cmd /C is unreliable over
	// OpenSSH on Windows (PowerShell/cmd nesting). Use mysql client's source command instead.
	line := formatMySQLWindowsCommandLine(cli, connectString)
	scriptPath := normalizeMySQLScriptPath(scriptFile)
	return line + ` -e "source ` + escapeMySQLSourcePath(scriptPath) + `"`
}

func normalizeMySQLScriptPath(path string) string {
	return strings.ReplaceAll(path, `\`, `/`)
}

func escapeMySQLSourcePath(path string) string {
	return strings.ReplaceAll(path, `"`, `\"`)
}

func formatMySQLWindowsCommandLine(cli, connectString string) string {
	parts := append([]string{cli}, MySQLExecArgv(connectString)...)
	quoted := make([]string, len(parts))
	for i, p := range parts {
		if strings.ContainsAny(p, " \t\"") {
			quoted[i] = `"` + strings.ReplaceAll(p, `"`, `""`) + `"`
		} else {
			quoted[i] = p
		}
	}
	return strings.Join(quoted, " ")
}

func quoteWindowsPath(path string) string {
	if strings.ContainsAny(path, " \t") {
		return `"` + strings.ReplaceAll(path, `"`, `""`) + `"`
	}
	return path
}

// SQLCmdConnectArgs splits ConnectString into sqlcmd client flags.
func SQLCmdConnectArgs(connectString string) []string {
	return strings.Fields(strings.TrimSpace(connectString))
}

// SQLCmdExecArgv returns argv for exec.Command(sqlcmd, argv...).
func SQLCmdExecArgv(connectString string, extra ...string) []string {
	args := append([]string{}, SQLCmdConnectArgs(connectString)...)
	return append(args, extra...)
}

// FormatSQLCmdCLIInvocation builds a shell-safe sqlcmd command (Unix/bash).
func FormatSQLCmdCLIInvocation(cli, connectString string, extra ...string) string {
	parts := append([]string{cli}, SQLCmdExecArgv(connectString, extra...)...)
	quoted := make([]string, len(parts))
	for i, p := range parts {
		quoted[i] = platform.ShellQuoteUnix(p)
	}
	return strings.Join(quoted, " ")
}

// FormatSQLCmdScriptExec builds sqlcmd -i for the target OS.
func FormatSQLCmdScriptExec(targetOS, cli, connectString, scriptFile string) string {
	if targetOS == platform.OSWindows {
		// Use backslashes: C:/Users/... makes sqlcmd treat "/Users" as -U (OS auth conflict with -E).
		path := quoteWindowsPath(formatSQLCmdWindowsScriptPath(scriptFile))
		return formatWindowsCLIWithConnect(cli, connectString, "-i", path)
	}
	return FormatSQLCmdCLIInvocation(cli, connectString, "-i", scriptFile)
}

func formatSQLCmdWindowsScriptPath(path string) string {
	return strings.ReplaceAll(path, `/`, `\`)
}

// FormatSQLCmdAdHocRemoteCmd builds sqlcmd -Q for remote SSH execution.
func FormatSQLCmdAdHocRemoteCmd(targetOS, cli, connectString, sql string) string {
	if targetOS == platform.OSWindows {
		parts := append([]string{cli}, SQLCmdExecArgv(connectString, "-Q", sql)...)
		quoted := make([]string, len(parts))
		for i, p := range parts {
			if strings.ContainsAny(p, " \t\"") {
				quoted[i] = `"` + strings.ReplaceAll(p, `"`, `""`) + `"`
			} else {
				quoted[i] = p
			}
		}
		return strings.Join(quoted, " ")
	}
	return FormatSQLCmdCLIInvocation(cli, connectString, "-Q", sql)
}

// BuildRemoteSQLExecCmd builds the remote shell command to execute a SQL script file.
// tmpFile must be an absolute path on the remote host (SFTP upload target).
func BuildRemoteSQLExecCmd(cfg *config.Config, targetOS, tmpFile string) string {
	if cfg.LoginCmd != "" {
		return fmt.Sprintf("%s < %s", cfg.LoginCmd, tmpFile)
	}
	cli := cfg.ResolveCLIForExec()
	switch cfg.DBType {
	case "mysql":
		return FormatMySQLScriptRedirectForOS(targetOS, cli, cfg.ConnectString, tmpFile)
	case "postgresql":
		return formatPostgreSQLRemoteExec(targetOS, cli, cfg.ConnectString, tmpFile)
	case "mssql":
		return FormatSQLCmdScriptExec(targetOS, cli, cfg.ConnectString, tmpFile)
	default:
		return formatOracleStyleRemoteExec(targetOS, cli, cfg.ConnectString, tmpFile)
	}
}

func formatPostgreSQLRemoteExec(targetOS, cli, connectString, scriptFile string) string {
	if targetOS == platform.OSWindows {
		path := quoteWindowsPath(normalizeMySQLScriptPath(scriptFile))
		return formatWindowsCLIWithConnect(cli, connectString, "-f", path)
	}
	return fmt.Sprintf("%s %s -f %s", cli, connectString, scriptFile)
}

func formatOracleStyleRemoteExec(targetOS, cli, connectString, scriptFile string) string {
	atFile := "@" + scriptFile
	if targetOS == platform.OSWindows {
		atFile = "@" + normalizeMySQLScriptPath(scriptFile)
	}
	return fmt.Sprintf("%s -S %s %s", cli, connectString, atFile)
}

func formatWindowsCLIWithConnect(cli, connectString string, extraArgs ...string) string {
	parts := append([]string{cli}, strings.Fields(connectString)...)
	parts = append(parts, extraArgs...)
	quoted := make([]string, len(parts))
	for i, p := range parts {
		if strings.ContainsAny(p, " \t\"") {
			quoted[i] = `"` + strings.ReplaceAll(p, `"`, `""`) + `"`
		} else {
			quoted[i] = p
		}
	}
	return strings.Join(quoted, " ")
}

// MySQLExecArgv returns argv for exec.Command(mysql, argv...).
// --defaults-file must be the first mysql client option (MySQL requirement).
func MySQLExecArgv(connectString string, extra ...string) []string {
	connectArgs := sortMySQLDefaultsFileFirst(MySQLConnectArgs(connectString))
	args := append([]string{}, connectArgs...)
	args = append(args, MySQLDefaultClientArgs...)
	return append(args, extra...)
}

// sortMySQLDefaultsFileFirst moves --defaults-file[=path] to the front of client option lists.
func sortMySQLDefaultsFileFirst(args []string) []string {
	var defaults, rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--defaults-file" && i+1 < len(args) {
			defaults = append(defaults, a, args[i+1])
			i++
			continue
		}
		if strings.HasPrefix(a, "--defaults-file=") {
			defaults = append(defaults, a)
			continue
		}
		rest = append(rest, a)
	}
	return append(defaults, rest...)
}

// BuildLocalSQLExecCmd builds exec.Cmd for local SQL execution.
// scriptFile is optional; when set the CLI reads SQL from that path.
// sql is always provided and used for stdin-based execution.
//
// On Windows: commands are built without a bash/shell wrapper using exec.Command directly.
// On Unix:    existing behaviour is preserved (bash -c for shell redirect / source-cmd).
func BuildLocalSQLExecCmd(ctx context.Context, cfg *config.Config, sql, scriptFile string) *exec.Cmd {
	// LoginCmd always takes priority: feed SQL via stdin through the user's command.
	if cfg.LoginCmd != "" {
		prog, args := platform.WrapLocalSourceCmd(platform.LocalOS(), cfg.SourceCmd, cfg.LoginCmd)
		cmd := exec.CommandContext(ctx, prog, args...)
		cmd.Stdin = strings.NewReader(sql + "\nexit\n")
		return cmd
	}

	cli := cfg.ResolveCLIForExec()

	if platform.LocalOS() == platform.OSWindows {
		return buildLocalWindowsExec(ctx, cfg, cli, sql, scriptFile)
	}

	// Unix path (original logic).
	if cfg.SourceCmd == "" {
		return buildLocalDirectSQLExec(ctx, cfg, cli, sql, scriptFile)
	}
	return buildLocalSourcedSQLExec(ctx, cfg, cli, sql, scriptFile)
}

// ── Windows local execution ────────────────────────────────────────────────

// buildLocalWindowsExec builds exec.Cmd for Windows local execution.
// Never uses bash; uses cmd /C when SourceCmd is set.
func buildLocalWindowsExec(ctx context.Context, cfg *config.Config, cli, sql, scriptFile string) *exec.Cmd {
	if cfg.SourceCmd == "" {
		return buildWindowsDirectExec(ctx, cfg, cli, sql, scriptFile)
	}
	return buildWindowsSourcedExec(ctx, cfg, cli, sql, scriptFile)
}

// buildWindowsDirectExec calls the DB CLI directly via exec.Command (no shell wrapper).
func buildWindowsDirectExec(ctx context.Context, cfg *config.Config, cli, sql, scriptFile string) *exec.Cmd {
	switch cfg.DBType {
	case "mysql":
		// MySQL on Windows: feed script via stdin (no bash redirect).
		args := MySQLExecArgv(cfg.ConnectString)
		cmd := exec.CommandContext(ctx, cli, args...)
		payload := sql
		if scriptFile != "" {
			if b, err := os.ReadFile(scriptFile); err == nil {
				payload = string(b)
			}
		}
		cmd.Stdin = strings.NewReader(payload + "\n")
		return cmd

	case "postgresql":
		if scriptFile != "" {
			return exec.CommandContext(ctx, cli, append(strings.Fields(cfg.ConnectString), "-f", scriptFile)...)
		}
		return exec.CommandContext(ctx, cli, append(strings.Fields(cfg.ConnectString), "-c", sql)...)

	case "mssql":
		if scriptFile != "" {
			return exec.CommandContext(ctx, cli, SQLCmdExecArgv(cfg.ConnectString, "-i", scriptFile)...)
		}
		return exec.CommandContext(ctx, cli, SQLCmdExecArgv(cfg.ConnectString, "-Q", sql)...)

	default: // oracle (sqlplus), dameng (disql)
		args := []string{"-S"}
		if cfg.ConnectString != "" {
			args = append(args, cfg.ConnectString)
		}
		if scriptFile != "" {
			args = append(args, "@"+scriptFile)
		}
		cmd := exec.CommandContext(ctx, cli, args...)
		if scriptFile == "" {
			cmd.Stdin = strings.NewReader(sql + "\nexit\n")
		}
		return cmd
	}
}

// buildWindowsSourcedExec runs the DB CLI via cmd /C "call env.bat && cli ..."
// to load environment variables from a Windows batch file before execution.
func buildWindowsSourcedExec(ctx context.Context, cfg *config.Config, cli, sql, scriptFile string) *exec.Cmd {
	var inner string
	var useStdin bool

	switch cfg.DBType {
	case "mysql":
		args := MySQLExecArgv(cfg.ConnectString)
		quoted := make([]string, len(args)+1)
		quoted[0] = cli
		for i, a := range args {
			quoted[i+1] = a
		}
		inner = strings.Join(quoted, " ")
		useStdin = true

	case "postgresql":
		connArgs := strings.Fields(cfg.ConnectString)
		if scriptFile != "" {
			connArgs = append(connArgs, "-f", scriptFile)
		} else {
			connArgs = append(connArgs, "-c", sql)
		}
		parts := make([]string, len(connArgs)+1)
		parts[0] = cli
		copy(parts[1:], connArgs)
		inner = strings.Join(parts, " ")

	case "mssql":
		args := SQLCmdExecArgv(cfg.ConnectString)
		if scriptFile != "" {
			args = append(args, "-i", scriptFile)
		} else {
			args = append(args, "-Q", sql)
		}
		parts := make([]string, len(args)+1)
		parts[0] = cli
		copy(parts[1:], args)
		inner = strings.Join(parts, " ")

	default: // oracle, dameng
		args := []string{"-S"}
		if cfg.ConnectString != "" {
			args = append(args, cfg.ConnectString)
		}
		if scriptFile != "" {
			args = append(args, "@"+scriptFile)
		} else {
			useStdin = true
		}
		parts := make([]string, len(args)+1)
		parts[0] = cli
		copy(parts[1:], args)
		inner = strings.Join(parts, " ")
	}

	src := cfg.SourceCmd
	fullCmd := fmt.Sprintf("call %s && %s", src, inner)
	cmd := exec.CommandContext(ctx, "cmd", "/C", fullCmd)
	if useStdin {
		exitStr := "\nexit\n"
		if cfg.DBType == "mysql" {
			exitStr = "\n"
		}
		cmd.Stdin = strings.NewReader(sql + exitStr)
	}
	return cmd
}

// ── Unix local execution (original logic, preserved) ──────────────────────

func buildLocalDirectSQLExec(ctx context.Context, cfg *config.Config, cli, sql, scriptFile string) *exec.Cmd {
	switch cfg.DBType {
	case "mysql":
		if scriptFile != "" {
			fullCmd := FormatMySQLScriptRedirect(cli, cfg.ConnectString, scriptFile)
			return exec.CommandContext(ctx, "bash", "-c", fullCmd)
		}
		return exec.CommandContext(ctx, cli, MySQLExecArgv(cfg.ConnectString, "-e", sql)...)
	case "postgresql":
		if scriptFile != "" {
			return exec.CommandContext(ctx, cli, cfg.ConnectString, "-f", scriptFile)
		}
		return exec.CommandContext(ctx, cli, cfg.ConnectString, "-c", sql)
	case "mssql":
		if scriptFile != "" {
			return exec.CommandContext(ctx, cli, SQLCmdExecArgv(cfg.ConnectString, "-i", scriptFile)...)
		}
		return exec.CommandContext(ctx, cli, SQLCmdExecArgv(cfg.ConnectString, "-Q", sql)...)
	default:
		args := []string{"-S"}
		if cfg.ConnectString != "" {
			args = append(args, cfg.ConnectString)
		}
		if scriptFile != "" {
			args = append(args, "@"+scriptFile)
		}
		cmd := exec.CommandContext(ctx, cli, args...)
		if scriptFile == "" {
			cmd.Stdin = strings.NewReader(sql + "\nexit\n")
		}
		return cmd
	}
}

func buildLocalSourcedSQLExec(ctx context.Context, cfg *config.Config, cli, sql, scriptFile string) *exec.Cmd {
	var fullCmd string
	var useStdin bool
	switch cfg.DBType {
	case "mysql":
		if scriptFile != "" {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatMySQLScriptRedirect(cli, cfg.ConnectString, scriptFile))
		} else {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatMySQLCLIInvocation(cli, cfg.ConnectString, "-e", sql))
		}
	case "postgresql":
		if scriptFile != "" {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatCLIInvocation(cli, cfg.ConnectString, "-f", scriptFile))
		} else {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatCLIInvocation(cli, cfg.ConnectString, "-c", sql))
		}
	case "mssql":
		if scriptFile != "" {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatSQLCmdCLIInvocation(cli, cfg.ConnectString, "-i", scriptFile))
		} else {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatSQLCmdCLIInvocation(cli, cfg.ConnectString, "-Q", sql))
		}
	default:
		args := []string{"-S"}
		if cfg.ConnectString != "" {
			args = append(args, cfg.ConnectString)
		}
		if scriptFile != "" {
			args = append(args, "@"+scriptFile)
		} else {
			useStdin = true
		}
		fullCmd = WrapSourceCmd(cfg.SourceCmd, FormatCLIInvocation(cli, args...))
	}
	cmd := exec.CommandContext(ctx, "bash", "-c", fullCmd)
	if useStdin {
		cmd.Stdin = strings.NewReader(sql + "\nexit\n")
	}
	return cmd
}

// BuildLocalOSExecCmd builds exec.Cmd for local OS/shell command execution with -s support.
func BuildLocalOSExecCmd(ctx context.Context, cfg *config.Config, command string) *exec.Cmd {
	if platform.LocalOS() == platform.OSWindows {
		prog, args := platform.WrapLocalSourceCmd(platform.OSWindows, cfg.SourceCmd, command)
		return exec.CommandContext(ctx, prog, args...)
	}
	return exec.CommandContext(ctx, "bash", "-c", WrapSourceCmd(cfg.SourceCmd, command))
}
