package connector

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
)

// SSHConnector implements Connector for SSH-based yasql execution
type SSHConnector struct {
	cfg       *config.Config
	pool      *SSHConnectionPool
	connected bool
}

// WrapCmd wraps a command so that the user's shell profile is loaded first.
// If SourceCmd is set (-s flag), use that; otherwise use "bash --login" to
// auto-load the user's .bash_profile / .profile regardless of OS.
// Remote env file existence is checked once in Connect, not on every wrapped command.
// Exported so executor can use it via type assertion.
func (c *SSHConnector) WrapCmd(cmd string) string {
	if c.cfg.SourceCmd != "" {
		return c.cfg.SourceCmd + " && " + cmd
	}
	// bash --login loads user profile automatically (.bash_profile, .profile, etc.)
	// This works across Linux, AIX, and other Unix systems.
	return fmt.Sprintf("bash --login -c %s", shellQuote(cmd))
}

// shellQuote wraps a string in single quotes, escaping embedded single quotes.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// randomHeredocMarker generates a unique heredoc marker to avoid collision with content
func randomHeredocMarker(prefix string) string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err == nil {
		return fmt.Sprintf("%s_%s", prefix, hex.EncodeToString(b[:]))
	}
	return fmt.Sprintf("%s_%d", prefix, os.Getpid())
}

// runCmd executes a command on the remote host.
// Uses the command directly via SSH session (heredoc/pipe commands work natively).
func (c *SSHConnector) runCmd(session *ssh.Session, cmd string) ([]byte, error) {
	logger.Debug("[ssh] runCmd: executing %d bytes\n", len(cmd))
	output, err := session.CombinedOutput(cmd)
	logger.Debug("[ssh] runCmd: got %d bytes, err=%v\n", len(output), err)
	cleaned := stripSttyWarnings(string(output))
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
	// Connect the pool
	if err := c.pool.Connect(ctx); err != nil {
		return err
	}

	c.connected = true

	if c.cfg.DebugMode {
		logger.Debug("SSH connector initialized with connection pool\n")
	}

	if c.cfg.SSHSourceExistenceCheck != "" {
		sTest, err := c.pool.NewSession()
		if err != nil {
			return fmt.Errorf("failed to create SSH session for source file check: %w", err)
		}
		if c.cfg.DebugMode {
			logger.Debug("Verifying remote -s file: %s\n", c.cfg.SSHSourceExistenceCheck)
		}
		out, err := c.runCmd(sTest, c.cfg.SSHSourceExistenceCheck)
		sTest.Close()
		if err != nil {
			return fmt.Errorf("source file not found on remote host (check -s path): %w\n%s", err, string(out))
		}
	}

	// Skip CLI check if using custom login command
	if c.cfg.LoginCmd != "" {
		return nil
	}

	// Verify DB CLI is available on remote host (new session; SSH Session is one-shot per Run)
	session, err := c.pool.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create SSH session for CLI verification: %w", err)
	}
	defer session.Close()

	cli := c.cfg.DefaultCLI()
	checkCmd := c.WrapCmd(fmt.Sprintf("which %s", cli))

	if c.cfg.DebugMode {
		logger.Debug("Checking DB CLI command: %s\n", checkCmd)
	}

	output, err := c.runCmd(session, checkCmd)
	if err != nil {
		return fmt.Errorf("DB CLI '%s' not found on remote host '%s'.\nPlease ensure it is installed, or use --login-cmd to specify a custom login command.\nOutput: %s", cli, c.cfg.SSHHost, string(output))
	}

	if c.cfg.DebugMode {
		logger.Debug("DB CLI found: %s\n", strings.TrimSpace(string(output)))
	}

	return nil
}

// buildSSHSQLExecCmd builds the command string to execute a SQL temp file on remote host.
// The returned command is already wrapped with profile loading via wrapCmd.
func (c *SSHConnector) buildSSHSQLExecCmd(tmpFile string) string {
	var cmd string
	if c.cfg.LoginCmd != "" {
		cmd = fmt.Sprintf("%s < %s", c.cfg.LoginCmd, tmpFile)
	} else {
		cli := c.cfg.DefaultCLI()
		switch c.cfg.DBType {
		case "mysql":
			cmd = fmt.Sprintf("%s %s < %s", cli, c.cfg.ConnectString, tmpFile)
		case "postgresql":
			cmd = fmt.Sprintf("%s %s -f %s", cli, c.cfg.ConnectString, tmpFile)
		default:
			// yasql, sqlplus, disql: @file syntax
			cmd = fmt.Sprintf("%s -S %s @%s", cli, c.cfg.ConnectString, tmpFile)
		}
	}
	return c.WrapCmd(cmd)
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

// executeSQLTwoStep uploads SQL to remote temp file then executes it.
// This matches the proven working pattern from executor.executeSQLViaSSHUpload.
func (c *SSHConnector) executeSQLTwoStep(ctx context.Context, sql string) (string, error) {
	tmpFile := fmt.Sprintf("/tmp/ytop_q_%d.sql", os.Getpid())

	sql = WrapSQLSuppressScriptEcho(c.cfg.DBType, sql)
	sql = EnsureSQLStatementTerminator(sql, c.cfg.DBType)

	// Step 1: Upload SQL to remote temp file using heredoc (no profile needed for cat)
	delim := randomHeredocMarker("YASTOP")
	uploadCmd := fmt.Sprintf("cat > %s << '%s'\n%s\nexit\n%s", tmpFile, delim, sql, delim)
	if c.cfg.DebugMode {
		logger.Debug("[ssh] SQL: %s\n", strings.ReplaceAll(sql, "\n", " "))
		logger.Debug("[ssh] Upload command: cat > %s << 'YASTOP_EOF' ...\n", tmpFile)
	}

	uploadOutput, err := c.ExecuteCommand(ctx, uploadCmd)
	if err != nil {
		return "", fmt.Errorf("failed to upload SQL to remote host: %w, output: %s", err, uploadOutput)
	}

	// Step 2: Execute the temp file (profile loaded via buildSSHSQLExecCmd -> wrapCmd)
	execCmd := c.buildSSHSQLExecCmd(tmpFile)
	if c.cfg.DebugMode {
		logger.Debug("[ssh] Execute command: %s\n", execCmd)
	}

	output, err := c.ExecuteCommand(ctx, execCmd)
	if err != nil {
		return output, fmt.Errorf("SSH SQL execution failed: %w", err)
	}

	// Step 3: Cleanup temp file (best effort, ignore errors)
	if !c.cfg.DebugMode {
		c.ExecuteCommand(ctx, fmt.Sprintf("rm -f %s", tmpFile))
	}

	if c.cfg.DebugMode {
		logger.Debug("[ssh] Output (%d bytes):\n%s\n", len(output), output)
	}

	return output, nil
}

// Close closes the SSH connection
func (c *SSHConnector) Close() error {
	if c.pool != nil {
		return c.pool.Close()
	}
	return nil
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

	if c.cfg.DebugMode {
		logger.Debug("SSH command: %s\n", command)
	}

	// Execute command
	output, err := c.runCmd(session, command)
	if err != nil {
		return string(output), fmt.Errorf("SSH command execution failed: %w", err)
	}

	if c.cfg.DebugMode {
		logger.Debug("Output: %s\n", string(output))
	}

	return string(output), nil
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
		return outputBuffer.String(), nil
	}

	if waitErr != nil {
		return outputBuffer.String(), fmt.Errorf("SSH command execution failed: %w", waitErr)
	}

	return outputBuffer.String(), nil
}

