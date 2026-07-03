package connector

import (
	"context"
	"fmt"
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
