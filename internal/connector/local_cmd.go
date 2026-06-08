package connector

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/platform"
)

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

	cli := cfg.DefaultCLI()

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
