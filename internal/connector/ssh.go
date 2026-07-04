package connector

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
)

// SSHConnector implements Connector for SSH-based yasql execution
type SSHConnector struct {
	cfg       *config.Config
	pool      *SSHConnectionPool
	connected bool
}

// WrapCmd wraps a command for the remote target OS (Unix bash or Windows cmd /C).
// Exported so executor can use it via type assertion.
func (c *SSHConnector) WrapCmd(cmd string) string {
	return platform.WrapRemoteCmd(c.cfg.TargetOS, c.cfg.SourceCmd, cmd)
}

// runCmd executes a command on the remote host via SSH session.
func (c *SSHConnector) runCmd(session *ssh.Session, cmd string) ([]byte, error) {
	logger.Debug("SSH command: %s\n", cmd)
	output, err := session.CombinedOutput(cmd)
	cleaned := stripSttyWarnings(string(output))
	logger.DebugCommandOutput("ssh", cleaned, err)
	return []byte(cleaned), err
}

// NewSSHConnector creates a new SSH connector
func NewSSHConnector(cfg *config.Config) *SSHConnector {
	return &SSHConnector{
		cfg:  cfg,
		pool: NewSSHConnectionPool(cfg, 10), // Pool size of 10
	}
}

// Connect establishes SSH connection
func (c *SSHConnector) Connect(ctx context.Context) error {
	logger.DebugStep("ssh-connect", fmt.Sprintf("host=%s user=%s db=%s", c.cfg.SSHHost, c.cfg.SSHUser, c.cfg.DBType))
	logger.DebugKeyVal("SSHHost", c.cfg.SSHHost)
	logger.DebugKeyVal("SSHUser", c.cfg.SSHUser)
	logger.DebugKeyVal("DBType", c.cfg.DBType)
	logger.DebugKeyVal("ConnectString", c.cfg.ConnectString)
	logger.DebugKeyVal("LoginCmd", c.cfg.LoginCmd)
	logger.DebugKeyVal("SourceCmd", c.cfg.SourceCmd)

	// Connect the pool
	if err := c.pool.Connect(ctx); err != nil {
		logger.DebugStep("ssh-connect FAILED", err.Error())
		return err
	}

	c.connected = true

	// Resolve target OS (auto-detect unless --target-os was set).
	if c.cfg.TargetOS == "" {
		client := c.pool.Client()
		c.cfg.TargetOS = platform.DetectRemoteOS(ctx, client, logger.Debug)
	} else {
		logger.DebugKeyVal("TargetOS", c.cfg.TargetOS+" (explicit)")
	}
	logger.DebugKeyVal("TargetOS", c.cfg.TargetOS)

	config.AdaptSourceCmdForWindowsSSH(c.cfg)
	c.cfg.ApplyMssqlSSHWindowsConnectDefaults()
	if c.cfg.DebugMode {
		if c.cfg.SourceCmd != "" {
			logger.DebugKeyVal("SourceCmd(final)", c.cfg.SourceCmd)
		}
		logger.DebugKeyVal("ConnectString(final)", c.cfg.ConnectString)
	}

	if c.cfg.DBType == "yashandb" && c.cfg.TargetOS == platform.OSWindows {
		err := fmt.Errorf(
			"YashanDB is not supported on a Windows SSH target (detected OS=windows).\n" +
				"  Use SSH to a Linux/Unix host, or set --target-os unix only when the remote is Unix.")
		logger.DebugStep("ssh-connect FAILED", err.Error())
		return err
	}

	if c.cfg.DebugMode {
		logger.Debug("SSH connector initialized with connection pool\n")
	}

	if c.cfg.SSHSourceExistenceCheck != "" {
		sTest, err := c.pool.NewSession()
		if err != nil {
			return fmt.Errorf("failed to create SSH session for source file check: %w", err)
		}
		checkCmd := platform.SourceEnvFileCheckCmd(c.cfg.TargetOS, c.cfg.SSHSourceExistenceCheck)
		out, err := c.runCmd(sTest, checkCmd)
		sTest.Close()
		if err != nil {
			return fmt.Errorf("source file not found on remote host (check -s path): %w\n%s", err, string(out))
		}
	}

	// Skip CLI check if using custom login command
	if c.cfg.LoginCmd != "" {
		logger.DebugStep("ssh-connect OK", "login-cmd provided; skipped CLI check")
		return nil
	}

	// Verify DB CLI is available on remote host (new session; SSH Session is one-shot per Run)
	cliPath, err := c.resolveRemoteCLIPath(ctx)
	if err != nil {
		return err
	}

	c.cfg.RemoteCLIPath = cliPath
	logger.DebugStep("ssh-connect OK", "CLI="+cliPath)
	logger.DebugKeyVal("CLIPath", cliPath)
	return nil
}

// resolveRemoteCLIPath finds the DB CLI on the remote host (where/which, then MSSQL registry on Windows).
func (c *SSHConnector) resolveRemoteCLIPath(ctx context.Context) (string, error) {
	session, err := c.pool.NewSession()
	if err != nil {
		logger.DebugStep("ssh-connect FAILED", err.Error())
		return "", fmt.Errorf("failed to create SSH session for CLI verification: %w", err)
	}
	defer session.Close()

	cli := c.cfg.DefaultCLI()
	checkInner := platform.CheckRemoteCLICmd(c.cfg.TargetOS, cli)
	checkCmd := c.WrapCmd(checkInner)

	logger.DebugSection("ssh-cli-check")
	logger.DebugKeyVal("CLI", cli)
	logger.DebugKeyVal("TargetOS", c.cfg.TargetOS)
	logger.DebugKeyVal("CheckCmd", checkCmd)

	output, err := c.runCmd(session, checkCmd)
	outStr := strings.TrimSpace(string(output))
	if err == nil {
		if cliPath := platform.TrimCLICheckOutput(outStr); cliPath != "" {
			return cliPath, nil
		}
	}

	if c.cfg.DBType == "mssql" && c.cfg.TargetOS == platform.OSWindows {
		cliPath, regErr := c.resolveMssqlCLIViaRegistry()
		if regErr == nil && cliPath != "" {
			logger.DebugStep("ssh-cli-check", "sqlcmd resolved via registry")
			return cliPath, nil
		}
		if regErr != nil {
			logger.DebugStep("ssh-cli-check registry FAILED", regErr.Error())
		}
	}

	hint := buildCLIHint(c.cfg.DBType, c.cfg.TargetOS, c.cfg.SourceCmd)
	logger.DebugStep("ssh-cli-check FAILED", "CLI not found")
	return "", fmt.Errorf(
		"DB CLI '%s' not found on remote host '%s' (targetOS=%s).\n"+
			"  Check command: %s\n"+
			"  Remote output: %s\n"+
			"%s",
		cli, c.cfg.SSHHost, c.cfg.TargetOS, checkCmd, outStr, hint,
	)
}

func (c *SSHConnector) resolveMssqlCLIViaRegistry() (string, error) {
	session, err := c.pool.NewSession()
	if err != nil {
		return "", fmt.Errorf("registry probe session: %w", err)
	}
	defer session.Close()

	probeCmd := c.WrapCmd(platform.BuildWindowsMssqlRegistryProbeCmd())
	logger.DebugKeyVal("MssqlRegistryProbe", probeCmd)

	output, err := c.runCmd(session, probeCmd)
	outStr := string(output)
	if err != nil {
		return "", fmt.Errorf("registry probe command failed: %w\n%s", err, outStr)
	}

	sqlcmdPath, tcpPort, parseErr := platform.ParseWindowsMssqlRegistryProbeOutput(outStr)
	if parseErr != nil {
		return "", parseErr
	}
	c.cfg.ApplyMssqlRegistryPort(tcpPort)
	if tcpPort != "" {
		logger.DebugKeyVal("MssqlRegistryPort", tcpPort)
		if c.cfg.DebugMode {
			logger.DebugKeyVal("ConnectString(after-port)", c.cfg.ConnectString)
		}
	}
	return sqlcmdPath, nil
}

// buildSSHSQLExecCmd builds the command string to execute a SQL temp file on remote host.
// The returned command is already wrapped with profile loading via WrapCmd.
func (c *SSHConnector) buildSSHSQLExecCmd(tmpFile string) string {
	return c.WrapCmd(BuildRemoteSQLExecCmd(c.cfg, c.cfg.TargetOS, tmpFile))
}

// ExecuteQuery executes a SQL query via SSH using two-step upload+execute pattern
func (c *SSHConnector) ExecuteQuery(ctx context.Context, sql string) ([][]string, error) {
	if !c.connected {
		return nil, fmt.Errorf("not connected")
	}

	output, err := c.executeSQLTwoStep(ctx, sql)
	if err != nil {
		return nil, err
	}

	rows, parseErr := parseYasqlOutput(output)
	if c.cfg.DebugMode {
		logger.Debug("[ssh] Parsed %d rows\n", len(rows))
	}
	return rows, parseErr
}

// ExecuteQueryWithHeader executes a SQL query and returns header + data rows
func (c *SSHConnector) ExecuteQueryWithHeader(ctx context.Context, sql string) (header []string, rows [][]string, err error) {
	if !c.connected {
		return nil, nil, fmt.Errorf("not connected")
	}

	output, err := c.executeSQLTwoStep(ctx, sql)
	if err != nil {
		return nil, nil, err
	}

	return ParseYasqlOutputWithHeader(output)
}

// executeSQLTwoStep uploads SQL via SFTP and executes it on the remote host.
func (c *SSHConnector) executeSQLTwoStep(ctx context.Context, sql string) (string, error) {
	sql = WrapSQLSuppressScriptEcho(c.cfg.DBType, sql)
	sql = EnsureSQLStatementTerminator(sql, c.cfg.DBType)

	logger.DebugSection("ssh-sql-query")
	logger.Debug("[ssh] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))

	return c.ExecuteRemoteSQLScript(ctx, []byte(sql), remoteScriptBasename("q"))
}

// Close closes the SSH connection
func (c *SSHConnector) Close() error {
	if c.pool != nil {
		err := c.pool.Close()
		c.connected = false
		return err
	}
	c.connected = false
	return nil
}

// Reconnect closes the current SSH session and runs Connect again (monitor retry).
func (c *SSHConnector) Reconnect(ctx context.Context) error {
	if c.pool != nil {
		_ = c.pool.Close()
	}
	c.connected = false
	return c.Connect(ctx)
}

// IsConnected returns connection status
func (c *SSHConnector) IsConnected() bool {
	return c.connected && c.pool != nil && c.pool.IsConnected()
}

// ExecuteCommand executes a shell command via SSH and returns raw output
func (c *SSHConnector) ExecuteCommand(ctx context.Context, command string) (string, error) {
	if !c.connected {
		return "", fmt.Errorf("not connected")
	}

	// Create new session from pool
	session, err := c.pool.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	output, err := c.runCmd(session, command)
	outputStr := string(output)
	if err != nil {
		return outputStr, fmt.Errorf("SSH command execution failed: %w", err)
	}

	return outputStr, nil
}

// ExecuteCommandRealtime executes a command via SSH with real-time output streaming
func (c *SSHConnector) ExecuteCommandRealtime(ctx context.Context, command string) (string, error) {
	if !c.connected {
		return "", fmt.Errorf("not connected")
	}

	// Create new session from pool
	session, err := c.pool.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()

	if c.cfg.DebugMode {
		logger.Debug("SSH command (realtime): %s\n", command)
	}

	// Get stdout and stderr pipes
	stdout, err := session.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stdout pipe: %w", err)
	}

	stderr, err := session.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stderr pipe: %w", err)
	}

	if err := session.Start(command); err != nil {
		return "", fmt.Errorf("failed to start SSH command: %w", err)
	}

	// Buffer to collect all output
	var outputBuffer strings.Builder
	var bufferMutex sync.Mutex

	var wg sync.WaitGroup
	wg.Add(2)

	// Context cancellation: close session to unblock Wait() and Read()
	go func() {
		<-ctx.Done()
		_ = session.Signal(ssh.SIGTERM)
		time.Sleep(100 * time.Millisecond)
		session.Close()
	}()

	// Read stdout in real-time byte by byte for immediate display
	go func() {
		defer wg.Done()
		buf := make([]byte, 1)
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				if buf[0] == '\n' {
					os.Stdout.Write([]byte("\r\n"))
					bufferMutex.Lock()
					outputBuffer.WriteByte('\n')
					bufferMutex.Unlock()
				} else {
					os.Stdout.Write(buf[:n])
					bufferMutex.Lock()
					outputBuffer.Write(buf[:n])
					bufferMutex.Unlock()
				}
			}
			if err != nil {
				return
			}
		}
	}()

	// Read stderr in real-time byte by byte for immediate display
	go func() {
		defer wg.Done()
		buf := make([]byte, 1)
		for {
			n, err := stderr.Read(buf)
			if n > 0 {
				if buf[0] == '\n' {
					os.Stderr.Write([]byte("\r\n"))
					bufferMutex.Lock()
					outputBuffer.WriteByte('\n')
					bufferMutex.Unlock()
				} else {
					os.Stderr.Write(buf[:n])
					bufferMutex.Lock()
					outputBuffer.Write(buf[:n])
					bufferMutex.Unlock()
				}
			}
			if err != nil {
				return
			}
		}
	}()

	// Wait for command to complete (unblocked by command exit or context cancel)
	waitErr := session.Wait()

	// Wait for readers to drain remaining buffered data
	wg.Wait()

	if ctx.Err() == context.Canceled {
		result := outputBuffer.String()
		if c.cfg.DebugMode {
			logger.DebugCommandOutput("ssh-realtime", result, ctx.Err())
		}
		return result, nil
	}

	if waitErr != nil {
		result := outputBuffer.String()
		if c.cfg.DebugMode {
			logger.DebugCommandOutput("ssh-realtime", result, waitErr)
		}
		return result, fmt.Errorf("SSH command execution failed: %w", waitErr)
	}

	result := outputBuffer.String()
	if c.cfg.DebugMode {
		logger.DebugCommandOutput("ssh-realtime", result, nil)
	}
	return result, nil
}

// ErrSSHRetriesExhausted is returned when monitor mode retried SSH operations
// the maximum number of times without success.
var ErrSSHRetriesExhausted = errors.New("ssh retries exhausted")

// MonitorSSHMaxRetries is the number of reconnect attempts in monitor TUI mode.
const MonitorSSHMaxRetries = 3

// IsRecoverableSSHError reports whether err likely indicates a broken SSH/SFTP session
// (as opposed to a SQL or configuration error).
func IsRecoverableSSHError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	patterns := []string{
		"not connected",
		"ssh connection failed",
		"failed to create ssh session",
		"ssh client not available",
		"ssh command execution failed",
		"sftp upload failed",
		"sftp upload verify failed",
		"connection reset",
		"broken pipe",
		"use of closed network connection",
		"i/o timeout",
		"no route to host",
		"connection refused",
		"network is unreachable",
		"ssh: handshake failed",
		"connection timed out",
		"eof",
	}
	for _, p := range patterns {
		if strings.Contains(msg, p) {
			return true
		}
	}
	return false
}
