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
			fullCmd := FormatCLIInvocation(cli, cfg.ConnectString) + " < " + shellQuote(scriptFile)
			return exec.CommandContext(ctx, "bash", "-c", fullCmd)
		}
		return exec.CommandContext(ctx, cli, cfg.ConnectString, "-e", sql)
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
				FormatCLIInvocation(cli, cfg.ConnectString)+" < "+shellQuote(scriptFile))
		} else {
			fullCmd = WrapSourceCmd(cfg.SourceCmd,
				FormatCLIInvocation(cli, cfg.ConnectString, "-e", sql))
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
