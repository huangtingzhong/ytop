package connector

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
)

// LocalConnector implements Connector for local yasql execution
type LocalConnector struct {
	cfg       *config.Config
	connected bool
}

// NewLocalConnector creates a new local connector
func NewLocalConnector(cfg *config.Config) *LocalConnector {
	return &LocalConnector{
		cfg: cfg,
	}
}

// Connect establishes the connection (for local, just verify yasql is available)
func (c *LocalConnector) Connect(ctx context.Context) error {
	if c.cfg.LoginCmd != "" {
		c.connected = true
		return nil
	}
	// Use `which` to verify CLI exists; source env first if specified
	cli := c.cfg.DefaultCLI()
	checkCmd := WrapSourceCmd(c.cfg.SourceCmd, fmt.Sprintf("which %s", cli))
	cmd := exec.CommandContext(ctx, "bash", "-c", checkCmd)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("DB CLI '%s' not found or not executable.\nPlease ensure it is installed and in PATH, or use --login-cmd to specify a custom login command.\nHint: use -s to source env file first (e.g. -s ~/.bash_profile).", cli)
	}
	c.connected = true
	return nil
}

// buildSQLCmd builds the exec.Cmd to run SQL via DB CLI or custom login command
func (c *LocalConnector) buildSQLCmd(ctx context.Context, sql string) *exec.Cmd {
	sql = WrapSQLSuppressScriptEcho(c.cfg.DBType, sql)
	sql = EnsureSQLStatementTerminator(sql, c.cfg.DBType)
	return BuildLocalSQLExecCmd(ctx, c.cfg, sql, "")
}

// ExecuteQuery executes a SQL query via DB CLI
func (c *LocalConnector) ExecuteQuery(ctx context.Context, sql string) ([][]string, error) {
	if !c.connected {
		return nil, fmt.Errorf("not connected")
	}

	cmd := c.buildSQLCmd(ctx, sql)
	if c.cfg.DebugMode {
		logger.Debug("[local] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))
		logger.Debug("[local] Command: %v\n", cmd.Args)
	}

	output, err := cmd.CombinedOutput()
	if c.cfg.DebugMode {
		logger.Debug("[local] Output (%d bytes):\n%s\n", len(output), string(output))
	}
	if err != nil {
		return nil, fmt.Errorf("SQL execution failed: %w, output: %s", err, string(output))
	}

	rows, parseErr := parseYasqlOutput(string(output))
	if c.cfg.DebugMode {
		logger.Debug("[local] Parsed %d rows\n", len(rows))
	}
	return rows, parseErr
}

// ExecuteQueryWithHeader executes a SQL query and returns header + data rows
func (c *LocalConnector) ExecuteQueryWithHeader(ctx context.Context, sql string) (header []string, rows [][]string, err error) {
	if !c.connected {
		return nil, nil, fmt.Errorf("not connected")
	}

	cmd := c.buildSQLCmd(ctx, sql)
	if c.cfg.DebugMode {
		logger.Debug("[local] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))
		logger.Debug("[local] Command: %v\n", cmd.Args)
	}

	output, err := cmd.CombinedOutput()
	if c.cfg.DebugMode {
		logger.Debug("[local] Output (%d bytes):\n%s\n", len(output), string(output))
	}
	if err != nil {
		return nil, nil, fmt.Errorf("SQL execution failed: %w, output: %s", err, string(output))
	}

	return ParseYasqlOutputWithHeader(string(output))
}

// Close closes the connection
func (c *LocalConnector) Close() error {
	c.connected = false
	return nil
}

// IsConnected returns connection status
func (c *LocalConnector) IsConnected() bool {
	return c.connected
}
