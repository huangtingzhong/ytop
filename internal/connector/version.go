package connector

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
	"github.com/yihan/ytop/internal/scripts"
)

// CLIVersionArgs returns CLI flags used to print client version for a DB type.
func CLIVersionArgs(dbType string) []string {
	switch dbType {
	case "oracle":
		return []string{"-V"}
	case "mysql", "postgresql":
		return []string{"--version"}
	case "mssql":
		return []string{"-?"}
	case "dameng":
		return []string{"-v"}
	default:
		return []string{"-v"}
	}
}

// DetectCLIVersionLocal runs the DB CLI version command on the local machine.
func DetectCLIVersionLocal(ctx context.Context, cfg *config.Config) (string, error) {
	cli := cliForVersionCheck(cfg)
	args := CLIVersionArgs(cfg.DBType)
	inner := FormatCLIInvocation(cli, args...)
	prog, argv := platform.WrapLocalSourceCmd(platform.LocalOS(), cfg.SourceCmd, inner)

	logger.DebugSection("version-detect")
	logger.Debug("Local command: %s %v\n", prog, argv)

	cmd := exec.CommandContext(ctx, prog, argv...)
	output, err := cmd.CombinedOutput()
	out := strings.TrimSpace(string(output))
	logger.DebugCommandOutput("version-detect-local", string(output), err)
	if err != nil {
		return "", fmt.Errorf("detect DB CLI version (%s %v): %w: %s", prog, argv, err, out)
	}
	version := scripts.ExtractVersionFromText(out)
	if version == "" {
		return "", fmt.Errorf("detect DB CLI version: no version token in output: %s", out)
	}
	return version, nil
}

// DetectCLIVersion detects DB CLI version locally or on the SSH target after Connect.
func DetectCLIVersion(ctx context.Context, cfg *config.Config, conn Connector) (string, error) {
	if conn == nil {
		return DetectCLIVersionLocal(ctx, cfg)
	}
	if cfg.ConnectionMode == "ssh" {
		if sshConn, ok := conn.(*SSHConnector); ok {
			return sshConn.detectCLIVersion(ctx)
		}
	}
	return DetectCLIVersionLocal(ctx, cfg)
}

func cliForVersionCheck(cfg *config.Config) string {
	if cfg.RemoteCLIPath != "" {
		return cfg.RemoteCLIPath
	}
	if cfg.LoginCmd != "" {
		fields := strings.Fields(cfg.LoginCmd)
		if len(fields) > 0 {
			return fields[0]
		}
	}
	return cfg.ResolveCLIForExec()
}

func (c *SSHConnector) detectCLIVersion(ctx context.Context) (string, error) {
	session, err := c.pool.NewSession()
	if err != nil {
		return "", fmt.Errorf("create SSH session for version detect: %w", err)
	}
	defer session.Close()

	cli := cliForVersionCheck(c.cfg)
	args := CLIVersionArgs(c.cfg.DBType)
	inner := FormatCLIInvocation(cli, args...)
	cmd := c.WrapCmd(inner)

	logger.DebugSection("version-detect")
	logger.DebugKeyVal("VersionCmd", cmd)

	output, err := c.runCmd(session, cmd)
	out := strings.TrimSpace(string(output))
	if err != nil {
		return "", fmt.Errorf("detect remote DB CLI version (%s): %w: %s", cmd, err, out)
	}
	version := scripts.ExtractVersionFromText(out)
	if version == "" {
		return "", fmt.Errorf("detect remote DB CLI version: no version token in output: %s", out)
	}
	logger.Debug("[version] detected remote DB CLI version: %s\n", version)
	return version, nil
}

// InitDBVersion fills cfg.DBVersion when empty and sets scripts.CurrentDBVersion.
func InitDBVersion(ctx context.Context, cfg *config.Config, conn Connector) {
	if strings.TrimSpace(cfg.DBVersion) != "" {
		scripts.CurrentDBVersion = strings.TrimSpace(cfg.DBVersion)
		return
	}
	version, err := DetectCLIVersion(ctx, cfg, conn)
	if err != nil {
		if cfg.DebugMode {
			logger.Debug("[version] auto-detect skipped: %v\n", err)
		}
		return
	}
	cfg.DBVersion = version
	scripts.CurrentDBVersion = version
	if cfg.DebugMode {
		logger.Debug("[version] using DB version: %s\n", version)
	}
}

// InitDBVersionFromConfig initializes script version without a DB connector (local CLI only).
func InitDBVersionFromConfig(ctx context.Context, cfg *config.Config) {
	if strings.TrimSpace(cfg.DBVersion) != "" {
		scripts.CurrentDBVersion = strings.TrimSpace(cfg.DBVersion)
		return
	}
	if cfg.ConnectionMode != "local" {
		return
	}
	version, err := DetectCLIVersionLocal(ctx, cfg)
	if err != nil {
		if cfg.DebugMode {
			logger.Debug("[version] local auto-detect skipped: %v\n", err)
		}
		return
	}
	cfg.DBVersion = version
	scripts.CurrentDBVersion = version
}
