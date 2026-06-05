package connector

import (
	"context"
	"os/exec"
	"strings"

	"github.com/yihan/ytop/internal/config"
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
	parts = append(parts, shellQuote(cli))
	for _, a := range args {
		parts = append(parts, shellQuote(a))
	}
	return strings.Join(parts, " ")
}

// MySQLDefaultClientArgs are always passed to the mysql CLI (table output for aligned columns).
var MySQLDefaultClientArgs = []string{"-t"}

// MySQLConnectArgs splits ConnectString into separate mysql client flags.
func MySQLConnectArgs(connectString string) []string {
	return strings.Fields(strings.TrimSpace(connectString))
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
		quoted[i] = shellQuote(p)
	}
	return strings.Join(quoted, " ")
}

// FormatMySQLScriptRedirect builds: mysql [flags...] < 'script.sql'
func FormatMySQLScriptRedirect(cli, connectString, scriptFile string) string {
	return FormatMySQLCLIInvocation(cli, connectString) + " < " + shellQuote(scriptFile)
}

// MySQLExecArgv returns argv for exec.Command(mysql, argv...).
func MySQLExecArgv(connectString string, extra ...string) []string {
	args := append([]string{}, MySQLDefaultClientArgs...)
	args = append(args, MySQLConnectArgs(connectString)...)
	return append(args, extra...)
}

// BuildLocalSQLExecCmd builds exec.Cmd for local SQL execution.
// scriptFile is optional; when set the CLI reads SQL from that path (@file, -f, or redirect).
// sql is used for stdin-based execution (login-cmd and yasql/sqlplus ad-hoc).
func BuildLocalSQLExecCmd(ctx context.Context, cfg *config.Config, sql, scriptFile string) *exec.Cmd {
	if cfg.LoginCmd != "" {
		fullCmd := WrapSourceCmd(cfg.SourceCmd, cfg.LoginCmd)
		cmd := exec.CommandContext(ctx, "bash", "-c", fullCmd)
		cmd.Stdin = strings.NewReader(sql + "\nexit\n")
		return cmd
	}

	cli := cfg.DefaultCLI()
	if cfg.SourceCmd == "" {
		return buildLocalDirectSQLExec(ctx, cfg, cli, sql, scriptFile)
	}
	return buildLocalSourcedSQLExec(ctx, cfg, cli, sql, scriptFile)
}

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
	return exec.CommandContext(ctx, "bash", "-c", WrapSourceCmd(cfg.SourceCmd, command))
}
