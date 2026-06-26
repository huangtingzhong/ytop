package executor

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
	"github.com/yihan/ytop/internal/scripts"
	"github.com/yihan/ytop/internal/terminal"
	"github.com/yihan/ytop/internal/utils"
)

// Executor handles script and command execution
type Executor struct {
	cfg  *config.Config
	conn connector.Connector
}

// NewExecutor creates a new executor
func NewExecutor(cfg *config.Config, conn connector.Connector) *Executor {
	return &Executor{
		cfg:  cfg,
		conn: conn,
	}
}

// ExecuteCommand executes a command or script
func (e *Executor) ExecuteCommand(ctx context.Context, input string) (string, error) {
	input = strings.TrimSpace(input)
	if input == "" {
		return "", fmt.Errorf("empty command")
	}

	// Check if it's a SQL script
	if scripts.IsSQLScriptInput(input) {
		return e.executeSQLScript(ctx, scripts.FirstToken(input))
	}

	if _, runArgs, kind, ok := parseSourceInvocation(input); ok {
		return e.executeSourceFile(ctx, scripts.FirstToken(input), runArgs, kind)
	}

	// Check if it's an OS command/script
	return e.executeOSCommand(ctx, input)
}

// executeSQLScript executes a SQL script
func (e *Executor) executeSQLScript(ctx context.Context, scriptName string) (string, error) {
	// Load script (handles both embedded and filesystem paths)
	scriptContent, err := scripts.GetSQLScript(scriptName)
	if err != nil {
		return "", err
	}

	if e.cfg.DebugMode {
		logger.Debug("Loaded script content:\n%s\n", scriptContent)
	}

	// Oracle sqlplus natively handles &var substitution with interactive prompts.
	// All other DB types: ytop handles variable substitution (no terminal or CLI doesn't support &var).
	if e.cfg.DBType != "oracle" {
		variables := e.findVariables(scriptContent)
		promptInfos := resolveVariablePromptInfos(scriptContent, variables)
		varMap := make(map[string]string)
		for _, variable := range variables {
			info := promptInfos[variable]
			printVariableHint(info.Hint)
			value := terminal.PromptInput(formatVariableInputPrompt(variable, info.Default), 256)
			if value == "" && info.Default != "" {
				value = info.Default
			}
			if e.cfg.DBType == "yashandb" {
				value = escapeYasqlSubstValue(value)
			}
			varMap[variable] = value
		}
		scriptContent = stripSQLPlusClientCommands(scriptContent)
		for variable, value := range varMap {
			scriptContent = e.replaceVariable(scriptContent, variable, value)
		}
	}

	// SSH mode: always upload and run on the remote host (respects TargetOS for Windows cmd vs Unix bash).
	if sqlScriptUsesSSH(e.cfg) {
		return e.executeSQLViaSSHUpload(ctx, scriptContent, scriptName)
	}

	return e.executeSQLDirect(ctx, scriptContent)
}

// executeSQLViaSSHUpload uploads script to remote host via SFTP and executes.
func (e *Executor) executeSQLViaSSHUpload(ctx context.Context, scriptContent, scriptName string) (string, error) {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return "", fmt.Errorf("not an SSH connection")
	}

	scriptForExec := connector.WrapSQLSuppressScriptEcho(e.cfg.DBType, scriptContent)
	scriptForExec = connector.EnsureSQLStatementTerminator(scriptForExec, e.cfg.DBType)

	logger.DebugStep("executor-ssh-script", scriptName)
	logger.DebugKeyVal("TargetOS", e.cfg.TargetOS)
	logger.DebugKeyVal("bytes", fmt.Sprintf("%d", len(scriptForExec)))

	basename := fmt.Sprintf("ytop_%s_%d.sql", filepath.Base(scriptName), os.Getpid())
	output, err := sshConn.ExecuteRemoteSQLScript(ctx, []byte(scriptForExec), basename)
	if e.cfg.DebugMode {
		logger.DebugCommandOutput("executor-ssh-script", output, err)
	}
	if err != nil {
		return output, fmt.Errorf("failed to execute script via SSH: %w", err)
	}
	return output, nil
}

// executeSQLDirect executes SQL directly via local yasql with temp file
func (e *Executor) executeSQLDirect(ctx context.Context, scriptContent string) (string, error) {
	// Create temporary script file
	tmpFile := platform.LocalTempPath(fmt.Sprintf("ytop_%d.sql", os.Getpid()))

	// Write script content to temp file (suppress CLI echo of script text for Oracle-style tools)
	scriptForExec := connector.WrapSQLSuppressScriptEcho(e.cfg.DBType, scriptContent)
	scriptForExec = connector.EnsureSQLStatementTerminator(scriptForExec, e.cfg.DBType)
	if err := os.WriteFile(tmpFile, []byte(scriptForExec), 0644); err != nil {
		return "", fmt.Errorf("failed to write temp script: %w", err)
	}

	// Ensure cleanup
	defer func() {
		if !e.cfg.DebugMode {
			os.Remove(tmpFile)
		}
	}()

	// Build command with @file
	cmd := connector.BuildLocalSQLExecCmd(ctx, e.cfg, scriptForExec, tmpFile)

	if e.cfg.DebugMode {
		logger.Debug("Executing SQL script locally: %v\n", cmd.Args)
	}

	output, err := cmd.CombinedOutput()
	outStr := string(output)
	if e.cfg.DebugMode {
		logger.DebugCommandOutput("local-sql-script", outStr, err)
	}
	if err != nil {
		return outStr, fmt.Errorf("SQL script execution failed: %w", err)
	}

	return outStr, nil
}

// executeOSCommand executes an OS command or script
func (e *Executor) executeOSCommand(ctx context.Context, input string) (string, error) {
	fields := strings.Fields(input)
	if len(fields) == 1 {
		scriptName := fields[0]
		scriptContent, err := scripts.GetOSScript(scriptName)
		if err == nil {
			return e.executeOSScript(ctx, scriptName, scriptContent, nil)
		}
		// Input looks like a script name (e.g. db_size.sl) but script not found:
		// do not run as shell command to avoid SSH and confusing "command not found"
		if strings.Contains(scriptName, ".") {
			return "", fmt.Errorf("script not found: %s", scriptName)
		}
	} else if len(fields) >= 2 {
		// "script.sh arg1 arg2" — first token may be an embedded/path OS script; pass args via bash -s
		scriptName := fields[0]
		scriptContent, err := scripts.GetOSScript(scriptName)
		if err == nil {
			return e.executeOSScript(ctx, scriptName, scriptContent, fields[1:])
		}
		// Looks like a script filename but not in script library
		if looksLikeOSScriptFilename(scriptName) {
			return "", fmt.Errorf("script not found: %s", scriptName)
		}
	}

	// Execute as shell command
	if e.cfg.ConnectionMode == "ssh" {
		return e.executeOSCommandViaSSH(ctx, input)
	}

	return e.executeOSCommandLocal(ctx, input)
}

func looksLikeOSScriptFilename(name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".sh", ".bash", ".zsh", ".ksh", ".c", ".py", ".ps1", ".bat", ".cmd":
		return true
	default:
		return false
	}
}

func randomHeredocMarker(prefix string) string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err == nil {
		return fmt.Sprintf("%s_%s", prefix, hex.EncodeToString(b[:]))
	}
	return fmt.Sprintf("%s_%d", prefix, os.Getpid())
}

// executeOSCommandViaSSH executes OS command via SSH with real-time output
func (e *Executor) executeOSCommandViaSSH(ctx context.Context, command string) (string, error) {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return "", fmt.Errorf("not an SSH connection")
	}

	command = sshConn.WrapCmd(command)
	return sshConn.ExecuteCommandRealtime(ctx, command)
}

// executeOSCommandLocal executes OS command locally with real-time output
func (e *Executor) executeOSCommandLocal(ctx context.Context, command string) (string, error) {
	cmd := connector.BuildLocalOSExecCmd(ctx, e.cfg, command)

	// Set process group ID so we can kill the entire process tree (platform-specific)
	setProcAttributes(cmd)

	// Create pipes for stdout and stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stdout pipe: %w", err)
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", fmt.Errorf("failed to create stderr pipe: %w", err)
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("failed to start command: %w", err)
	}

	// Buffer to collect all output
	var outputBuffer strings.Builder
	var bufferMutex sync.Mutex

	var wg sync.WaitGroup
	wg.Add(2)

	// Context cancellation: kill process to unblock Wait() and Read()
	go func() {
		<-ctx.Done()
		killProcessGroup(cmd)
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
	waitErr := cmd.Wait()

	// Wait for readers to drain remaining buffered data
	wg.Wait()

	if ctx.Err() == context.Canceled {
		result := outputBuffer.String()
		if e.cfg.DebugMode {
			logger.DebugCommandOutput("local-os-command", result, ctx.Err())
		}
		return result, nil
	}

	if waitErr != nil {
		result := outputBuffer.String()
		if e.cfg.DebugMode {
			logger.DebugCommandOutput("local-os-command", result, waitErr)
		}
		return result, fmt.Errorf("command failed: %w", waitErr)
	}

	result := outputBuffer.String()
	if e.cfg.DebugMode {
		logger.DebugCommandOutput("local-os-command", result, nil)
	}
	return result, nil
}

// effectiveTargetOS returns the OS where commands/scripts execute.
func (e *Executor) effectiveTargetOS() string {
	if e.cfg.ConnectionMode == "ssh" {
		if e.cfg.TargetOS != "" {
			return e.cfg.TargetOS
		}
		return platform.OSUnix
	}
	return platform.LocalOS()
}

func osScriptArtifactName(scriptName string) string {
	ext := filepath.Ext(scriptName)
	base := strings.TrimSuffix(filepath.Base(scriptName), ext)
	if base == "" {
		base = "script"
	}
	return fmt.Sprintf("ytop_%s_%d%s", base, os.Getpid(), ext)
}

// executeOSScript executes an embedded OS script using a runner matched to target OS and file extension.
func (e *Executor) executeOSScript(ctx context.Context, scriptName, scriptContent string, args []string) (string, error) {
	targetOS := e.effectiveTargetOS()
	kind := platform.OSScriptKindFromExt(scriptName)
	if !platform.OSScriptSupportedOn(kind, targetOS) {
		return "", platform.OSScriptMismatchError(scriptName, targetOS, kind)
	}

	pythonBin := e.cfg.Python
	if pythonBin == "" {
		pythonBin = platform.DefaultPythonBin(targetOS)
	}

	artifact := osScriptArtifactName(scriptName)

	if e.cfg.ConnectionMode == "ssh" {
		return e.executeOSScriptSSH(ctx, scriptContent, artifact, args, kind, pythonBin, targetOS)
	}
	return e.executeOSScriptLocal(ctx, scriptContent, artifact, args, kind, pythonBin, targetOS)
}

func (e *Executor) executeOSScriptLocal(ctx context.Context, scriptContent, artifact string, args []string, kind platform.OSScriptKind, pythonBin, targetOS string) (string, error) {
	scriptPath := platform.LocalTempPath(artifact)
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0644); err != nil {
		return "", fmt.Errorf("failed to write OS script: %w", err)
	}
	if !e.cfg.DebugMode {
		defer os.Remove(scriptPath)
	}

	cmd, err := platform.BuildOSScriptRunCmd(targetOS, scriptPath, args, kind, pythonBin)
	if err != nil {
		return "", err
	}
	if e.cfg.SourceCmd != "" {
		cmd = connector.WrapSourceCmd(e.cfg.SourceCmd, cmd)
	}
	if e.cfg.DebugMode {
		logger.Debug("Executing OS script locally: %s\n", cmd)
	}
	return e.executeOSCommandLocal(ctx, cmd)
}

func (e *Executor) executeOSScriptSSH(ctx context.Context, scriptContent, artifact string, args []string, kind platform.OSScriptKind, pythonBin, targetOS string) (string, error) {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return "", fmt.Errorf("not an SSH connection")
	}

	sftpPath, execPath, err := sshConn.UploadScriptSFTP(ctx, []byte(scriptContent), artifact)
	if err != nil {
		return "", fmt.Errorf("failed to upload OS script: %w", err)
	}

	if !e.cfg.DebugMode {
		defer sshConn.CleanupRemoteScript(sftpPath)
	}

	cmd, err := platform.BuildOSScriptRunCmd(targetOS, execPath, args, kind, pythonBin)
	if err != nil {
		return "", err
	}
	cmd = sshConn.WrapCmd(cmd)
	if e.cfg.DebugMode {
		logger.Debug("Executing OS script via SSH: %s\n", cmd)
	}
	return sshConn.ExecuteCommandRealtime(ctx, cmd)
}

// ExecuteAdHocSQL executes a single SQL statement directly
func (e *Executor) ExecuteAdHocSQL(ctx context.Context, sql string) (string, error) {
	sql = strings.TrimSpace(sql)
	if sql == "" {
		return "", fmt.Errorf("empty SQL statement")
	}

	// Execute based on connection mode
	if e.cfg.ConnectionMode == "ssh" {
		return e.executeAdHocSQLViaSSH(ctx, sql)
	}

	return e.executeAdHocSQLLocal(ctx, sql)
}

// executeAdHocSQLViaSSH executes ad-hoc SQL via SSH
func (e *Executor) executeAdHocSQLViaSSH(ctx context.Context, sql string) (string, error) {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return "", fmt.Errorf("not an SSH connection")
	}

	sqlExec := connector.WrapSQLSuppressScriptEcho(e.cfg.DBType, sql)
	sqlExec = connector.EnsureSQLStatementTerminator(sqlExec, e.cfg.DBType)

	// If user provided a custom login command, run it via heredoc (same idea as -f path)
	if e.cfg.LoginCmd != "" {
		delim := randomHeredocMarker("YTOP_SQL")
		cmd := fmt.Sprintf("%s <<'%s'\n%s\nexit\n%s", e.cfg.LoginCmd, delim, sqlExec, delim)
		cmd = sshConn.WrapCmd(cmd)
		if e.cfg.DebugMode {
			logger.Debug("Executing ad-hoc SQL via SSH (login-cmd): %s\n", cmd)
		}
		return sshConn.ExecuteCommand(ctx, cmd)
	}

	cli := e.cfg.ResolveCLIForExec()
	var remoteCmd string
	switch e.cfg.DBType {
	case "mysql":
		remoteCmd = connector.FormatMySQLAdHocRemoteCmd(e.cfg.TargetOS, cli, e.cfg.ConnectString, sqlExec)
	case "postgresql":
		// psql: pass SQL with -c
		remoteCmd = fmt.Sprintf("%s %s -c %s",
			cli,
			e.cfg.ConnectString,
			utils.ShellEscape(sqlExec))
	case "mssql":
		remoteCmd = connector.FormatSQLCmdAdHocRemoteCmd(e.cfg.TargetOS, cli, e.cfg.ConnectString, sqlExec)
	default:
		// Windows remote has no bash heredoc; upload script and run via @file / disql.
		if e.cfg.TargetOS == platform.OSWindows {
			return sshConn.ExecuteRemoteSQLScript(ctx, []byte(sqlExec), connector.RemoteScriptBasename("q"))
		}
		delim := randomHeredocMarker("YTOP_SQL")
		remoteCmd = fmt.Sprintf("%s -S %s <<'%s'\n%s\nexit\n%s",
			cli,
			e.cfg.ConnectString,
			delim,
			sqlExec,
			delim)
	}

	remoteCmd = sshConn.WrapCmd(remoteCmd)

	if e.cfg.DebugMode {
		logger.Debug("Executing ad-hoc SQL via SSH: %s\n", remoteCmd)
	}

	return sshConn.ExecuteCommand(ctx, remoteCmd)
}

// executeAdHocSQLLocal executes ad-hoc SQL locally
func (e *Executor) executeAdHocSQLLocal(ctx context.Context, sql string) (string, error) {
	sqlExec := connector.WrapSQLSuppressScriptEcho(e.cfg.DBType, sql)
	sqlExec = connector.EnsureSQLStatementTerminator(sqlExec, e.cfg.DBType)

	cmd := connector.BuildLocalSQLExecCmd(ctx, e.cfg, sqlExec, "")
	if e.cfg.DebugMode {
		logger.Debug("Executing ad-hoc SQL locally: %v\n", cmd.Args)
	}
	output, err := cmd.CombinedOutput()
	outStr := string(output)
	if e.cfg.DebugMode {
		logger.DebugCommandOutput("local-sql-adhoc", outStr, err)
	}
	if err != nil {
		return outStr, fmt.Errorf("SQL execution failed: %w", err)
	}
	return outStr, nil
}

// yasqlDollarVar matches yasql $identifier substitution (e.g. $session in v$session).
var yasqlDollarVar = regexp.MustCompile(`\$([A-Za-z_][A-Za-z0-9_]*)`)

// escapeYasqlSubstValue rewrites $ident to #ident in user &var values before yasql runs.
// yasql scans the script for $name; \$ is invalid (YAS-04102). Scripts such as print_table.sql
// map # back to $ via REPLACE(..., '#', CHR(36)) inside PL/SQL.
func escapeYasqlSubstValue(value string) string {
	if value == "" || !strings.Contains(value, "$") {
		return value
	}
	return yasqlDollarVar.ReplaceAllString(value, `#$1`)
}

// findVariables finds all &var and &&var in script (skips -- / REM comment lines).
func (e *Executor) findVariables(script string) []string {
	return collectScriptVariables(script)
}

// replaceVariable replaces a variable in script (skips -- / REM comment lines).
func (e *Executor) replaceVariable(script, variable, value string) string {
	pattern := regexp.QuoteMeta(variable) + `\b`
	re := regexp.MustCompile(pattern)
	lines := splitScriptLines(script)
	for i, line := range lines {
		if isSQLCommentLine(line) {
			continue
		}
		lines[i] = re.ReplaceAllString(line, value)
	}
	return strings.Join(lines, "\n")
}

// splitSQLStatements splits SQL script into individual statements
func (e *Executor) splitSQLStatements(script string) []string {
	// Simple split by semicolon (can be improved for complex cases)
	statements := strings.Split(script, ";")
	var result []string

	for _, stmt := range statements {
		stmt = strings.TrimSpace(stmt)
		if stmt != "" {
			result = append(result, stmt)
		}
	}

	return result
}

// sqlScriptUsesSSH reports whether -f SQL scripts should be uploaded and executed on the SSH target.
func sqlScriptUsesSSH(cfg *config.Config) bool {
	return cfg.ConnectionMode == "ssh"
}

// isSQLPlusCommand checks if statement is a SQL*Plus command
func (e *Executor) isSQLPlusCommand(stmt string) bool {
	// Don't filter any commands - all SQL scripts have been tested and can be executed directly
	return false
}

// CopyScript copies a script file to specified destination
// For SSH mode: copies to remote server
// For local mode: copies to local filesystem
// Returns destination file path and error
func (e *Executor) CopyScript(ctx context.Context, scriptName, destPath string) (string, error) {
	// Load script content (handles both .sql and other files)
	var scriptContent string
	var err error

	if strings.HasSuffix(scriptName, ".sql") {
		scriptContent, err = scripts.GetSQLScript(scriptName)
	} else {
		scriptContent, err = scripts.LoadScriptByName(scriptName)
	}

	if err != nil {
		return "", fmt.Errorf("failed to load script: %w", err)
	}

	// Default destination uses target OS temp directory
	if destPath == "" {
		destPath = platform.DefaultScriptCopyDir(e.effectiveTargetOS())
	}

	// Ensure destination path ends with /
	if !strings.HasSuffix(destPath, "/") {
		destPath = destPath + "/"
	}

	destFile := destPath + filepath.Base(scriptName)

	// Copy based on connection mode
	if e.cfg.ConnectionMode == "ssh" {
		return destFile, e.copyScriptViaSSH(ctx, scriptContent, destFile)
	}

	return destFile, e.copyScriptLocal(scriptContent, destFile)
}

// copyScriptViaSSH copies script to remote server via SFTP (works on Unix and Windows targets).
func (e *Executor) copyScriptViaSSH(ctx context.Context, scriptContent, destFile string) error {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return fmt.Errorf("not an SSH connection")
	}

	if err := sshConn.UploadFileToPath(ctx, []byte(scriptContent), destFile); err != nil {
		return fmt.Errorf("failed to copy script to remote server: %w", err)
	}

	return nil
}

// copyScriptLocal copies script to local filesystem
func (e *Executor) copyScriptLocal(scriptContent, destFile string) error {
	// Write to local file
	if err := os.WriteFile(destFile, []byte(scriptContent), 0644); err != nil {
		return fmt.Errorf("failed to copy script to local path: %w", err)
	}

	// Verify file exists and check size
	fileInfo, err := os.Stat(destFile)
	if err != nil {
		return fmt.Errorf("failed to verify copied file: %w", err)
	}

	// Check if file size matches
	if fileInfo.Size() != int64(len(scriptContent)) {
		return fmt.Errorf("file size mismatch: expected %d bytes, got %d bytes", len(scriptContent), fileInfo.Size())
	}

	return nil
}
