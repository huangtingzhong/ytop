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
		if scripts.LastResolvedScript != "" && scripts.LastResolvedScript != scriptName {
			logger.Debug("Resolved script %q -> %q (DB version %s)\n",
				scriptName, scripts.LastResolvedScript, scripts.CurrentDBVersion)
		}
		logger.Debug("Loaded script content:\n%s\n", scriptContent)
	}

	// Oracle sqlplus natively handles &var substitution with interactive prompts.
	// All other DB types: ytop handles variable substitution (no terminal or CLI doesn't support &var).
	if e.cfg.DBType != "oracle" {
		promptOrder := resolveVariablePromptOrder(scriptContent)
		variables := promptOrder.Ordered
		lines := splitScriptLines(scriptContent)
		displayedPrompt := make(map[int]bool)
		promptInfos := resolveVariablePromptInfos(scriptContent, variables, displayedPrompt, promptOrder.PreludeHints)
		if e.cfg.DebugMode {
			logger.Debug("[script-variables] order_source=%s ordered=%v\n", promptOrder.Source, variables)
			debugLogScriptVariables(variables, promptInfos)
		}
		varMap := make(map[string]string)
		for i, variable := range variables {
			if e.cfg.DBType == "yashandb" {
				start, end := yashanDBPromptWindow(variables, i, lines, promptOrder.PreludeLineIdx)
				printYashanDBPromptBlocks(scriptContent, start, end, displayedPrompt)
			}
			info := promptInfos[variable]
			printVariableHint(info.Hint)
			rawValue := terminal.PromptInput(formatVariableInputPrompt(variable, info.Default), 256)
			value := rawValue
			source := "input"
			if value == "" && info.Default != "" {
				value = info.Default
				source = "default"
			}
			if e.cfg.DBType == "yashandb" {
				escaped := escapeYasqlSubstValue(value)
				if e.cfg.DebugMode && escaped != value {
					logger.Debug("Variable %s: yasql escape %q -> %q\n", variable, value, escaped)
				}
				value = escaped
			}
			varMap[variable] = value
			if e.cfg.DebugMode {
				debugLogVariableAssignment(variable, rawValue, value, source)
			}
		}
		beforeStrip := scriptContent
		scriptContent = stripSQLPlusClientCommands(scriptContent)
		if e.cfg.DebugMode && scriptContent != beforeStrip {
			logger.Debug("Stripped SQL*Plus client commands (ACCEPT/PROMPT/etc.)\n")
		}
		for _, variable := range variables {
			scriptContent = e.replaceVariable(scriptContent, variable, varMap[variable])
			if e.cfg.DebugMode {
				logger.Debug("Replaced %s with %q\n", variable, varMap[variable])
			}
		}
		if e.cfg.DebugMode && len(variables) > 0 {
			logger.DebugSection("script-after-substitution")
			logger.Debug("%s\n", scriptContent)
		}
	} else if e.cfg.DebugMode {
		logger.Debug("Oracle mode: variable substitution delegated to sqlplus\n")
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

func debugLogScriptVariables(variables []string, promptInfos map[string]variablePromptInfo) {
	logger.DebugSection("script-variables")
	if len(variables) == 0 {
		logger.Debug("No substitution variables found\n")
		return
	}
	logger.Debug("Found %d variable(s): %v\n", len(variables), variables)
	for _, variable := range variables {
		info := promptInfos[variable]
		logger.Debug("  %s: hint=%q default=%q\n", variable, info.Hint, info.Default)
	}
}

func debugLogVariableAssignment(variable, rawValue, finalValue, source string) {
	switch {
	case source == "default":
		logger.Debug("Variable %s = %q (from default, input was empty)\n", variable, finalValue)
	case rawValue != finalValue:
		logger.Debug("Variable %s: input=%q resolved=%q (from %s)\n", variable, rawValue, finalValue, source)
	default:
		logger.Debug("Variable %s = %q (from %s)\n", variable, finalValue, source)
	}
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

func parseSourceInvocation(input string) (source string, runArgs []string, kind scripts.SourceKind, ok bool) {
	fields := strings.Fields(strings.TrimSpace(input))
	if len(fields) == 0 {
		return "", nil, scripts.SourceKindNone, false
	}
	kind = scripts.SourceKindFromName(fields[0])
	if kind == scripts.SourceKindNone {
		return "", nil, scripts.SourceKindNone, false
	}
	return fields[0], fields[1:], kind, true
}

func escapeRunArgs(args []string) string {
	if len(args) == 0 {
		return ""
	}
	parts := make([]string, len(args))
	for i, a := range args {
		parts[i] = utils.ShellEscape(a)
	}
	return strings.Join(parts, " ")
}

func sourceArtifactNames(sourceName string, kind scripts.SourceKind) (srcFile, binFile string) {
	base := strings.TrimSuffix(filepath.Base(sourceName), filepath.Ext(sourceName))
	tag := fmt.Sprintf("ytop_%s_%d", base, os.Getpid())
	switch kind {
	case scripts.SourceKindC:
		return tag + ".c", tag
	case scripts.SourceKindPy:
		return tag + ".py", ""
	default:
		return tag, ""
	}
}

func (e *Executor) executeSourceFile(ctx context.Context, source string, runArgs []string, kind scripts.SourceKind) (string, error) {
	var content string
	var err error
	switch kind {
	case scripts.SourceKindC:
		content, err = scripts.GetCSource(source)
	case scripts.SourceKindPy:
		content, err = scripts.GetPySource(source)
	default:
		return "", fmt.Errorf("unsupported source kind")
	}
	if err != nil {
		return "", err
	}

	if e.cfg.DebugMode {
		logger.Debug("Loaded %s source (%d bytes)\n", filepath.Ext(source), len(content))
	}

	srcName, binName := sourceArtifactNames(source, kind)
	targetOS := e.cfg.TargetOS
	if e.cfg.ConnectionMode != "ssh" {
		targetOS = platform.LocalOS()
	}
	if targetOS == platform.OSWindows && kind == scripts.SourceKindC && binName != "" {
		binName += ".exe"
	}

	if e.cfg.ConnectionMode == "ssh" {
		return e.executeSourceFileSSH(ctx, content, srcName, binName, kind, runArgs, targetOS)
	}
	return e.executeSourceFileLocal(ctx, content, srcName, binName, kind, runArgs, targetOS)
}

func (e *Executor) executeSourceFileLocal(ctx context.Context, content, srcName, binName string, kind scripts.SourceKind, runArgs []string, targetOS string) (string, error) {
	srcPath := platform.LocalTempPath(srcName)
	workDir := filepath.Dir(srcPath)
	binPath := filepath.Join(workDir, binName)

	if err := os.WriteFile(srcPath, []byte(content), 0644); err != nil {
		return "", fmt.Errorf("failed to write source file: %w", err)
	}

	if !e.cfg.DebugMode {
		defer func() {
			os.Remove(srcPath)
			if binName != "" {
				os.Remove(binPath)
			}
			if kind == scripts.SourceKindPy {
				os.RemoveAll(filepath.Join(workDir, "__pycache__"))
			}
		}()
	}

	cmd := buildSourceRunCommand(e.cfg, targetOS, workDir, srcPath, binPath, kind, runArgs)
	if e.cfg.SourceCmd != "" {
		cmd = connector.WrapSourceCmd(e.cfg.SourceCmd, cmd)
	}

	if e.cfg.DebugMode {
		logger.Debug("Executing source file locally: %s\n", cmd)
	}
	return e.executeOSCommandLocal(ctx, cmd)
}

func (e *Executor) executeSourceFileSSH(ctx context.Context, content, srcName, binName string, kind scripts.SourceKind, runArgs []string, targetOS string) (string, error) {
	sshConn, ok := e.conn.(*connector.SSHConnector)
	if !ok {
		return "", fmt.Errorf("not an SSH connection")
	}

	sftpPath, execPath, err := sshConn.UploadScriptSFTP(ctx, []byte(content), srcName)
	if err != nil {
		return "", fmt.Errorf("failed to upload source file: %w", err)
	}

	workDir := filepath.Dir(execPath)
	binPath := filepath.Join(filepath.Dir(execPath), binName)
	if targetOS == platform.OSWindows {
		workDir = strings.ReplaceAll(workDir, `\`, `/`)
		binPath = workDir + "/" + binName
	}

	if !e.cfg.DebugMode {
		defer func() {
			sshConn.CleanupRemoteScript(sftpPath)
			if binName != "" {
				rmCmd := fmt.Sprintf("rm -f %s", platform.ShellQuoteUnix(binPath))
				if targetOS == platform.OSWindows {
					rmCmd = fmt.Sprintf("del /f /q %s", quoteWindowsCmdPath(binPath))
				}
				rmCmd = sshConn.WrapCmd(rmCmd)
				_, _ = sshConn.ExecuteCommand(ctx, rmCmd)
			}
		}()
	}

	cmd := buildSourceRunCommand(e.cfg, targetOS, workDir, execPath, binPath, kind, runArgs)
	cmd = sshConn.WrapCmd(cmd)

	if e.cfg.DebugMode {
		logger.Debug("Executing source file via SSH: %s\n", cmd)
	}
	return sshConn.ExecuteCommandRealtime(ctx, cmd)
}

func buildSourceRunCommand(cfg *config.Config, targetOS, workDir, srcPath, binPath string, kind scripts.SourceKind, runArgs []string) string {
	d := cfgDefaults(cfg)
	if targetOS == platform.OSWindows {
		return buildSourceRunWindows(d, workDir, srcPath, binPath, kind, runArgs)
	}
	return buildSourceRunUnix(d, workDir, srcPath, binPath, kind, runArgs)
}

type configWithDefaults struct {
	CC      string
	CFLAGS  string
	LDFLAGS string
	Python  string
}

func cfgDefaults(c *config.Config) configWithDefaults {
	cc := c.CC
	if cc == "" {
		cc = "gcc"
	}
	py := c.Python
	if py == "" {
		py = "python3"
	}
	return configWithDefaults{CC: cc, CFLAGS: c.CFLAGS, LDFLAGS: c.LDFLAGS, Python: py}
}

func buildSourceRunUnix(d configWithDefaults, workDir, srcPath, binPath string, kind scripts.SourceKind, runArgs []string) string {
	wd := platform.ShellQuoteUnix(workDir)
	src := platform.ShellQuoteUnix(srcPath)
	argsStr := escapeRunArgs(runArgs)

	switch kind {
	case scripts.SourceKindC:
		bin := platform.ShellQuoteUnix(binPath)
		compile := platform.ShellQuoteUnix(d.CC)
		if d.CFLAGS != "" {
			compile += " " + d.CFLAGS
		}
		compile += " -o " + bin + " " + src
		if d.LDFLAGS != "" {
			compile += " " + d.LDFLAGS
		}
		run := bin
		if argsStr != "" {
			run += " " + argsStr
		}
		return "cd " + wd + " && " + compile + " && " + run
	case scripts.SourceKindPy:
		py := platform.ShellQuoteUnix(d.Python)
		run := py + " -u " + src
		if argsStr != "" {
			run += " " + argsStr
		}
		return "cd " + wd + " && " + run
	default:
		return ""
	}
}

func buildSourceRunWindows(d configWithDefaults, workDir, srcPath, binPath string, kind scripts.SourceKind, runArgs []string) string {
	wd := quoteWindowsCmdPath(workDir)
	src := quoteWindowsCmdPath(srcPath)
	argsStr := escapeRunArgsWindows(runArgs)

	switch kind {
	case scripts.SourceKindC:
		bin := quoteWindowsCmdPath(binPath)
		compile := quoteWindowsCmdPath(d.CC) + " "
		if d.CFLAGS != "" {
			compile += d.CFLAGS + " "
		}
		compile += "-o " + bin + " " + src
		if d.LDFLAGS != "" {
			compile += " " + d.LDFLAGS
		}
		run := bin
		if argsStr != "" {
			run += " " + argsStr
		}
		return "cd /d " + wd + " && " + compile + " && " + run
	case scripts.SourceKindPy:
		run := quoteWindowsCmdPath(d.Python) + " -u " + src
		if argsStr != "" {
			run += " " + argsStr
		}
		return "cd /d " + wd + " && " + run
	default:
		return ""
	}
}

func quoteWindowsCmdPath(path string) string {
	path = strings.ReplaceAll(path, `/`, `\`)
	if strings.ContainsAny(path, " \t") {
		return `"` + strings.ReplaceAll(path, `"`, `""`) + `"`
	}
	return path
}

func escapeRunArgsWindows(args []string) string {
	if len(args) == 0 {
		return ""
	}
	parts := make([]string, len(args))
	for i, a := range args {
		if strings.ContainsAny(a, " \t\"") {
			parts[i] = `"` + strings.ReplaceAll(a, `"`, `""`) + `"`
		} else {
			parts[i] = a
		}
	}
	return strings.Join(parts, " ")
}
