package connector

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
)

// readSSHKey reads SSH private key from file
func readSSHKey(keyFile string) ([]byte, error) {
	key, err := os.ReadFile(keyFile)
	if err != nil {
		return nil, fmt.Errorf("failed to read SSH key file: %w", err)
	}
	return key, nil
}

// SSHConnectionPool manages SSH client connection (not sessions)
// Sessions are created on-demand and closed after use
type SSHConnectionPool struct {
	cfg       *config.Config
	client    *ssh.Client
	mu        sync.Mutex
	connected bool
}

// NewSSHConnectionPool creates a new SSH connection pool
func NewSSHConnectionPool(cfg *config.Config, maxSize int) *SSHConnectionPool {
	return &SSHConnectionPool{
		cfg: cfg,
	}
}

// Connect establishes the SSH connection
func (p *SSHConnectionPool) Connect(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.connected && p.client != nil {
		return nil
	}

	// Prepare SSH client config
	sshConfig := &ssh.ClientConfig{
		User:            p.cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(p.cfg.SSHTimeout) * time.Second,
	}

	// Add authentication method
	if p.cfg.SSHPassword != "" {
		sshConfig.Auth = append(sshConfig.Auth, ssh.Password(p.cfg.SSHPassword))
		sshConfig.Auth = append(sshConfig.Auth, ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
			answers := make([]string, len(questions))
			for i := range answers {
				answers[i] = p.cfg.SSHPassword
			}
			return answers, nil
		}))
	}

	if p.cfg.SSHKeyFile != "" {
		key, err := readSSHKey(p.cfg.SSHKeyFile)
		if err != nil {
			return fmt.Errorf("failed to read SSH key file '%s': %w", p.cfg.SSHKeyFile, err)
		}

		signer, err := ssh.ParsePrivateKey(key)
		if err != nil {
			return fmt.Errorf("failed to parse SSH key file '%s': %w", p.cfg.SSHKeyFile, err)
		}

		sshConfig.Auth = append(sshConfig.Auth, ssh.PublicKeys(signer))
	}

	// Connect to SSH server
	addr := fmt.Sprintf("%s:%d", p.cfg.SSHHost, p.cfg.SSHPort)

	// Build connection info for debugging
	var authMethod string
	if p.cfg.SSHPassword != "" && p.cfg.SSHKeyFile != "" {
		authMethod = "password + key"
	} else if p.cfg.SSHPassword != "" {
		authMethod = "password"
	} else if p.cfg.SSHKeyFile != "" {
		authMethod = "key"
	} else {
		authMethod = "none"
	}

	if p.cfg.DebugMode {
		logger.Debug("SSH Connection attempt:\n")
		logger.Debug("  Host: %s\n", p.cfg.SSHHost)
		logger.Debug("  Port: %d\n", p.cfg.SSHPort)
		logger.Debug("  User: %s\n", p.cfg.SSHUser)
		logger.Debug("  Auth: %s\n", authMethod)
		if p.cfg.SSHKeyFile != "" {
			logger.Debug("  Key file: %s\n", p.cfg.SSHKeyFile)
		}
	}

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		// Build detailed error message with connection info
		var errorMsg strings.Builder
		fmt.Fprintf(&errorMsg, "SSH connection failed:\n")
		fmt.Fprintf(&errorMsg, "  Host: %s\n", p.cfg.SSHHost)
		fmt.Fprintf(&errorMsg, "  Port: %d\n", p.cfg.SSHPort)
		fmt.Fprintf(&errorMsg, "  User: %s\n", p.cfg.SSHUser)
		fmt.Fprintf(&errorMsg, "  Auth method: %s\n", authMethod)
		if p.cfg.SSHKeyFile != "" {
			fmt.Fprintf(&errorMsg, "  Key file: %s\n", p.cfg.SSHKeyFile)
		}

		// Build test command for user
		fmt.Fprintf(&errorMsg, "\nTest command:\n")
		if p.cfg.SSHKeyFile != "" {
			// Use key file authentication
			fmt.Fprintf(&errorMsg, "  ssh -i %s -p %d %s@%s\n",
				p.cfg.SSHKeyFile, p.cfg.SSHPort, p.cfg.SSHUser, p.cfg.SSHHost)
		} else {
			// Use password authentication
			fmt.Fprintf(&errorMsg, "  ssh -p %d %s@%s\n",
				p.cfg.SSHPort, p.cfg.SSHUser, p.cfg.SSHHost)
		}

		fmt.Fprintf(&errorMsg, "\nOriginal error: %v\n", err)

		return fmt.Errorf("%s", errorMsg.String())
	}

	p.client = client
	p.connected = true

	if p.cfg.DebugMode {
		logger.Debug("SSH connection pool connected to %s\n", addr)
	}

	return nil
}

// NewSession creates a new SSH session from the pool's client
func (p *SSHConnectionPool) NewSession() (*ssh.Session, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if !p.connected || p.client == nil {
		return nil, fmt.Errorf("not connected")
	}

	session, err := p.client.NewSession()
	if err != nil {
		return nil, fmt.Errorf("failed to create SSH session: %w", err)
	}

	if p.cfg.DebugMode {
		logger.Debug("Created new SSH session from pool\n")
	}

	return session, nil
}

// Close closes the connection
func (p *SSHConnectionPool) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Close client
	if p.client != nil {
		err := p.client.Close()
		p.client = nil
		p.connected = false
		return err
	}

	return nil
}

// IsConnected returns connection status
func (p *SSHConnectionPool) IsConnected() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.connected && p.client != nil
}

// Client returns the underlying *ssh.Client for operations that require direct
// access to the SSH connection, such as SFTP file transfers.
// Returns nil when the pool is not connected.
func (p *SSHConnectionPool) Client() *ssh.Client {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.client
}

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

// resolveRemoteTempDir determines the absolute temp directory on the SSH target host.
func (c *SSHConnector) resolveRemoteTempDir(ctx context.Context) (string, error) {
	if c.cfg.RemoteTempDir != "" {
		return c.cfg.RemoteTempDir, nil
	}

	logger.DebugStep("ssh-resolve-tempdir", fmt.Sprintf("targetOS=%s", c.cfg.TargetOS))

	var probeCmd string
	if c.cfg.TargetOS == platform.OSWindows {
		// OpenSSH on Windows already invokes cmd.exe /c; avoid nested cmd /C.
		probeCmd = `echo %TEMP%`
	} else {
		probeCmd = `echo /tmp`
	}

	out, err := c.ExecuteCommand(ctx, probeCmd)
	if err != nil {
		logger.DebugStep("ssh-resolve-tempdir WARN", fmt.Sprintf("probe failed: %v; using default", err))
		c.cfg.RemoteTempDir = platform.ParseRemoteTempOutput(c.cfg.TargetOS, "")
	} else {
		c.cfg.RemoteTempDir = platform.ParseRemoteTempOutput(c.cfg.TargetOS, out)
	}

	logger.DebugKeyVal("RemoteTempDir", c.cfg.RemoteTempDir)
	return c.cfg.RemoteTempDir, nil
}

// UploadScriptSFTP uploads script bytes to the remote host via SFTP (required for all SSH uploads).
// Returns sftpPath (for delete/stat) and execPath (for mysql source / psql -f on the remote host).
func (c *SSHConnector) UploadScriptSFTP(ctx context.Context, content []byte, basename string) (sftpPath, execPath string, err error) {
	logger.DebugSection("ssh-sftp-upload")
	logger.DebugKeyVal("basename", basename)
	logger.DebugKeyVal("bytes", fmt.Sprintf("%d", len(content)))

	if _, err = c.resolveRemoteTempDir(ctx); err != nil {
		return "", "", err
	}

	sftpPath = platform.SFTPPath(c.cfg.TargetOS, c.cfg.RemoteTempDir, basename)
	execPath = platform.RemoteExecScriptPath(c.cfg.TargetOS, c.cfg.RemoteTempDir, basename)

	logger.DebugKeyVal("sftpPath", sftpPath)
	logger.DebugKeyVal("execPath", execPath)

	client := c.pool.Client()
	if client == nil {
		return "", "", fmt.Errorf("SSH client not available for SFTP upload")
	}

	if err = platform.UploadFileViaSFTP(client, content, sftpPath); err != nil {
		logger.DebugStep("ssh-sftp-upload FAILED", err.Error())
		return "", "", fmt.Errorf("SFTP upload failed for %q: %w", sftpPath, err)
	}

	if err = platform.VerifyFileViaSFTP(client, sftpPath); err != nil {
		logger.DebugStep("ssh-sftp-upload VERIFY FAILED", err.Error())
		return "", "", fmt.Errorf("SFTP upload verify failed for %q: %w", sftpPath, err)
	}

	logger.DebugStep("ssh-sftp-upload OK", execPath)
	return sftpPath, execPath, nil
}

// UploadFileToPath uploads bytes to an absolute remote path via SFTP.
func (c *SSHConnector) UploadFileToPath(_ context.Context, content []byte, remotePath string) error {
	logger.DebugSection("ssh-sftp-upload-path")
	logger.DebugKeyVal("remotePath", remotePath)
	logger.DebugKeyVal("bytes", fmt.Sprintf("%d", len(content)))

	client := c.pool.Client()
	if client == nil {
		return fmt.Errorf("SSH client not available for SFTP upload")
	}
	if err := platform.UploadFileViaSFTP(client, content, remotePath); err != nil {
		return fmt.Errorf("SFTP upload failed for %q: %w", remotePath, err)
	}
	return nil
}

// ExecuteRemoteSQLScript uploads SQL via SFTP, runs it on the remote host, and cleans up.
func (c *SSHConnector) ExecuteRemoteSQLScript(ctx context.Context, content []byte, basename string) (string, error) {
	sftpPath, execPath, err := c.UploadScriptSFTP(ctx, content, basename)
	if err != nil {
		return "", err
	}

	defer func() {
		if !c.cfg.DebugMode {
			c.CleanupRemoteScript(sftpPath)
		} else {
			logger.DebugKeyVal("debugKeepScript", execPath)
		}
	}()

	execCmd := c.buildSSHSQLExecCmd(execPath)
	logger.DebugKeyVal("ExecCmd", execCmd)

	output, err := c.ExecuteCommand(ctx, execCmd)
	if err != nil {
		return output, fmt.Errorf("SSH SQL execution failed: %w\nOutput: %s", err, output)
	}
	return output, nil
}

// CleanupRemoteScript removes a remote script file via SFTP (best-effort).
func (c *SSHConnector) CleanupRemoteScript(remotePath string) {
	if remotePath == "" {
		return
	}
	client := c.pool.Client()
	if client == nil {
		return
	}
	if err := platform.DeleteFileViaSFTP(client, remotePath); err != nil {
		logger.Debug("[ssh-sftp-cleanup] remove %q: %v\n", remotePath, err)
	} else {
		logger.Debug("[ssh-sftp-cleanup] removed %q\n", remotePath)
	}
}

// RemoteScriptBasename returns a unique script filename for SFTP upload.
func RemoteScriptBasename(prefix string) string {
	return remoteScriptBasename(prefix)
}

// remoteScriptBasename returns a unique script filename for SFTP upload.
func remoteScriptBasename(prefix string) string {
	return fmt.Sprintf("ytop_%s_%d_%d.sql", prefix, os.Getpid(), os.Getppid())
}

// FindLocalKey returns the path to an existing default SSH private key,
// or an empty string if none is found.
func FindLocalKey() string {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		logger.Debug("[ssh-init] cannot determine home directory: %v\n", err)
		return ""
	}
	defaultKey := filepath.Join(homeDir, ".ssh", "id_rsa")
	if _, err := os.Stat(defaultKey); err == nil {
		logger.Debug("[ssh-init] found existing key: %s\n", defaultKey)
		return defaultKey
	}
	logger.Debug("[ssh-init] no default key at %s\n", defaultKey)
	return ""
}

// EnsureLocalKey checks for an existing SSH key pair or generates one.
// Returns the path to the private key file.
func EnsureLocalKey(keyFile string) (string, error) {
	// If a specific key file is given, check it exists
	if keyFile != "" {
		if _, err := os.Stat(keyFile); err != nil {
			return "", fmt.Errorf("specified key file not found: %s", keyFile)
		}
		logger.Debug("[ssh-init] using specified key file: %s\n", keyFile)
		return keyFile, nil
	}

	// Try default key path
	if k := FindLocalKey(); k != "" {
		return k, nil
	}

	// No key found — generate one
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("cannot determine home directory: %w", err)
	}
	defaultKey := filepath.Join(homeDir, ".ssh", "id_rsa")

	fmt.Printf("No SSH key found at %s\n", defaultKey)
	fmt.Print("Generate a new RSA 2048 key pair? [Y/n] ")

	var answer string
	fmt.Scanln(&answer)
	answer = strings.TrimSpace(strings.ToLower(answer))
	if answer != "" && answer != "y" && answer != "yes" {
		logger.Debug("[ssh-init] key generation cancelled by user\n")
		return "", fmt.Errorf("SSH key generation cancelled")
	}

	// Ensure ~/.ssh directory exists
	sshDir := filepath.Join(homeDir, ".ssh")
	if err := os.MkdirAll(sshDir, 0700); err != nil {
		return "", fmt.Errorf("failed to create %s: %w", sshDir, err)
	}
	logger.Debug("[ssh-init] created directory: %s\n", sshDir)

	// Generate RSA 2048 key pair using pure Go (no dependency on ssh-keygen command)
	if err := generateRSAKeyPair(defaultKey); err != nil {
		return "", fmt.Errorf("failed to generate SSH key: %w", err)
	}

	logger.Debug("[ssh-init] generated new RSA 2048 key pair: %s\n", defaultKey)
	fmt.Printf("SSH key pair generated: %s\n", defaultKey)
	return defaultKey, nil
}

// ReadPublicKey reads the .pub file corresponding to the given private key
func ReadPublicKey(keyFile string) (string, error) {
	pubFile := keyFile + ".pub"
	logger.Debug("[ssh-init] reading public key from: %s\n", pubFile)

	data, err := os.ReadFile(pubFile)
	if err != nil {
		return "", fmt.Errorf("failed to read public key %s: %w", pubFile, err)
	}

	pubKey := strings.TrimSpace(string(data))
	logger.Debug("[ssh-init] public key loaded (%d bytes): %s...%s\n", len(pubKey), pubKey[:20], pubKey[len(pubKey)-20:])
	return pubKey, nil
}

// generateRSAKeyPair creates a 2048-bit RSA key pair in pure Go.
// Writes <basePath> (private) and <basePath>.pub (public in OpenSSH format).
func generateRSAKeyPair(basePath string) error {
	logger.Debug("[ssh-init] generating RSA 2048 key pair at %s\n", basePath)

	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("RSA key generation failed: %w", err)
	}

	// Write private key (PEM format, 0600)
	privFile, err := os.OpenFile(basePath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return fmt.Errorf("failed to create private key file: %w", err)
	}
	defer privFile.Close()

	if err := pem.Encode(privFile, &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privateKey),
	}); err != nil {
		return fmt.Errorf("failed to write private key: %w", err)
	}
	logger.Debug("[ssh-init] private key written: %s (0600)\n", basePath)

	// Write public key (OpenSSH authorized_keys format)
	pubKey, err := ssh.NewPublicKey(&privateKey.PublicKey)
	if err != nil {
		return fmt.Errorf("failed to derive SSH public key: %w", err)
	}

	pubFile, err := os.OpenFile(basePath+".pub", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return fmt.Errorf("failed to create public key file: %w", err)
	}
	defer pubFile.Close()

	if _, err := pubFile.Write(ssh.MarshalAuthorizedKey(pubKey)); err != nil {
		return fmt.Errorf("failed to write public key: %w", err)
	}
	logger.Debug("[ssh-init] public key written: %s.pub (0644)\n", basePath)

	return nil
}

// CopyPublicKeyToHost connects to the remote host using password authentication
// and appends the public key to the OS-appropriate authorized_keys file.
func CopyPublicKeyToHost(cfg *config.Config, pubKey string) error {
	client, addr, err := dialPasswordSSH(cfg)
	if err != nil {
		return err
	}
	defer client.Close()

	targetOS := resolveSSHTargetOS(cfg, client)
	logger.Debug("[ssh-init] target OS for key install: %s\n", targetOS)

	encoded := base64.StdEncoding.EncodeToString([]byte(pubKey))
	remoteCmd := platform.CopyPublicKeyRemoteCmd(targetOS, encoded)
	return runSSHInitRemoteCmd(client, addr, "write public key to remote host", remoteCmd)
}

// DeletePublicKeyFromHost connects to the remote host using key authentication
// and removes the matching public key line from the OS-appropriate authorized_keys file.
func DeletePublicKeyFromHost(cfg *config.Config, keyFile string, pubKey string) error {
	logger.Debug("[ssh-init] reading private key: %s\n", keyFile)

	key, err := readSSHKey(keyFile)
	if err != nil {
		logger.Debug("[ssh-init] failed to read key file: %v\n", err)
		return fmt.Errorf("failed to read SSH key file: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		logger.Debug("[ssh-init] failed to parse key: %v\n", err)
		return fmt.Errorf("failed to parse SSH key file: %w", err)
	}

	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] connecting to %s (user=%s, auth=key)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] connection failed: %v\n", err)
		return fmt.Errorf("SSH key auth to %s failed (passwordless login not configured?): %w", addr, err)
	}
	defer client.Close()
	logger.Debug("[ssh-init] connected to %s\n", addr)

	targetOS := resolveSSHTargetOS(cfg, client)
	logger.Debug("[ssh-init] target OS for key delete: %s\n", targetOS)

	encoded := base64.StdEncoding.EncodeToString([]byte(pubKey))
	remoteCmd := platform.DeletePublicKeyRemoteCmd(targetOS, encoded)
	return runSSHInitRemoteCmd(client, addr, "remove public key from remote host", remoteCmd)
}

// TestKeyAuth tests that key-based authentication works by connecting with the private key.
func TestKeyAuth(cfg *config.Config, keyFile string) error {
	logger.Debug("[ssh-init] reading private key: %s\n", keyFile)

	key, err := readSSHKey(keyFile)
	if err != nil {
		logger.Debug("[ssh-init] failed to read key file: %v\n", err)
		return fmt.Errorf("failed to read key file: %w", err)
	}

	signer, err := ssh.ParsePrivateKey(key)
	if err != nil {
		logger.Debug("[ssh-init] failed to parse key: %v\n", err)
		return fmt.Errorf("failed to parse private key: %w", err)
	}

	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] testing key auth to %s (user=%s)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] key auth test failed: %v\n", err)
		return fmt.Errorf("key-based authentication failed: %w", err)
	}
	client.Close()

	logger.Debug("[ssh-init] key auth test passed\n")
	return nil
}

func dialPasswordSSH(cfg *config.Config) (*ssh.Client, string, error) {
	sshConfig := &ssh.ClientConfig{
		User:            cfg.SSHUser,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         time.Duration(cfg.SSHTimeout) * time.Second,
		Auth: []ssh.AuthMethod{
			ssh.Password(cfg.SSHPassword),
			ssh.KeyboardInteractive(func(user, instruction string, questions []string, echos []bool) ([]string, error) {
				answers := make([]string, len(questions))
				for i := range answers {
					answers[i] = cfg.SSHPassword
				}
				return answers, nil
			}),
		},
	}

	addr := fmt.Sprintf("%s:%d", cfg.SSHHost, cfg.SSHPort)
	logger.Debug("[ssh-init] connecting to %s (user=%s, auth=password)\n", addr, cfg.SSHUser)

	client, err := ssh.Dial("tcp", addr, sshConfig)
	if err != nil {
		logger.Debug("[ssh-init] connection failed: %v\n", err)
		return nil, addr, fmt.Errorf("SSH connection to %s failed: %w", addr, err)
	}
	logger.Debug("[ssh-init] connected to %s\n", addr)
	return client, addr, nil
}

func resolveSSHTargetOS(cfg *config.Config, client *ssh.Client) string {
	if cfg.TargetOS != "" {
		logger.Debug("[ssh-init] using explicit target OS: %s\n", cfg.TargetOS)
		return cfg.TargetOS
	}
	return platform.DetectRemoteOS(context.Background(), client, logger.Debug)
}

func runSSHInitRemoteCmd(client *ssh.Client, addr, action, remoteCmd string) error {
	session, err := client.NewSession()
	if err != nil {
		return fmt.Errorf("failed to create SSH session: %w", err)
	}
	defer session.Close()

	logger.Debug("[ssh-init] remote command: %s\n", remoteCmd)

	output, err := session.CombinedOutput(remoteCmd)
	if err != nil {
		logger.Debug("[ssh-init] remote command failed: %v, output: %s\n", err, string(output))
		return fmt.Errorf("failed to %s: %w\n%s", action, err, string(output))
	}

	logger.Debug("[ssh-init] remote command succeeded, output: %s\n", strings.TrimSpace(string(output)))
	return nil
}
