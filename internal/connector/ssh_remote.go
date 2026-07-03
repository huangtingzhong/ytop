package connector

import (
	"context"
	"fmt"
	"os"

	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
)

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
