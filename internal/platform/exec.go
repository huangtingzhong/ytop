package platform

import (
	"context"
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	"unicode/utf16"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

// ResolveCLI finds the CLI executable for dbType on the local machine using exec.LookPath.
// On Windows, also retries with ".exe" suffix when the plain name is not found.
// yasqlPath is used when dbType is "yashandb"; defaults to "yasql" when empty.
func ResolveCLI(dbType, yasqlPath string) (string, error) {
	name := defaultCLIName(dbType, yasqlPath)

	path, err := exec.LookPath(name)
	if err == nil {
		return path, nil
	}
	firstErr := err

	// Windows: also try explicit .exe suffix when the name has no extension.
	if LocalOS() == OSWindows && !strings.Contains(filepath.Base(name), ".") {
		if path2, err2 := exec.LookPath(name + ".exe"); err2 == nil {
			return path2, nil
		}
	}

	pathEnv := os.Getenv("PATH")
	return "", fmt.Errorf(
		"CLI '%s' not found in PATH\n  LookPath error: %v\n  PATH=%s",
		name, firstErr, pathEnv,
	)
}

// ResolveLocalCLI finds the DB CLI on the local machine.
// When sourceCmd is set and the CLI is not on the current PATH, runs which/where after
// applying sourceCmd (aligned with SSH resolveRemoteCLIPath + WrapCmd).
func ResolveLocalCLI(ctx context.Context, dbType, yasqlPath, sourceCmd string) (string, error) {
	localOS := LocalOS()
	cliName := defaultCLIName(dbType, yasqlPath)

	if path, err := resolveCLIIfAbsolute(cliName); err != nil {
		return "", err
	} else if path != "" {
		return path, nil
	}

	if path, err := exec.LookPath(cliName); err == nil {
		return path, nil
	}

	if strings.TrimSpace(sourceCmd) != "" {
		path, err := resolveCLIAfterSource(ctx, localOS, cliName, sourceCmd)
		if err == nil {
			return path, nil
		}
		pathEnv := os.Getenv("PATH")
		return "", fmt.Errorf("%s\n  PATH=%s", err.Error(), pathEnv)
	}

	return ResolveCLI(dbType, yasqlPath)
}

func resolveCLIIfAbsolute(name string) (string, error) {
	if name == "" || !filepath.IsAbs(name) {
		return "", nil
	}
	info, err := os.Stat(name)
	if err != nil {
		return "", fmt.Errorf("CLI path not found or not executable: %s: %w", name, err)
	}
	if info.IsDir() {
		return "", fmt.Errorf("CLI path is a directory: %s", name)
	}
	if LocalOS() == OSUnix && info.Mode()&0111 == 0 {
		return "", fmt.Errorf("CLI path is not executable: %s", name)
	}
	return name, nil
}

func resolveCLIAfterSource(ctx context.Context, localOS, cliName, sourceCmd string) (string, error) {
	inner := CheckRemoteCLICmd(localOS, cliName)
	prog, args := WrapLocalSourceCmd(localOS, sourceCmd, inner)
	cmd := exec.CommandContext(ctx, prog, args...)
	output, err := cmd.CombinedOutput()
	outStr := strings.TrimSpace(string(output))
	if err != nil {
		return "", fmt.Errorf(
			"CLI '%s' not found after sourcing env.\n  Command: %s %v\n  Output: %s\n  Error: %v",
			cliName, prog, args, outStr, err,
		)
	}
	if path := TrimCLICheckOutput(outStr); path != "" {
		return path, nil
	}
	return "", fmt.Errorf("CLI '%s' not found after sourcing env (empty which/where output): %s", cliName, outStr)
}

// TrimCLICheckOutput returns the first line of which/where output.
func TrimCLICheckOutput(output string) string {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) == 0 {
		return ""
	}
	return strings.TrimSpace(strings.TrimRight(lines[0], "\r"))
}

// DefaultCLINameForDB returns the default CLI binary name for a DB type.
// Exported so connectors can display the expected CLI name in error messages.
func DefaultCLINameForDB(dbType, yasqlPath string) string {
	return defaultCLIName(dbType, yasqlPath)
}

// defaultCLIName returns the default CLI binary name for a DB type.
func defaultCLIName(dbType, yasqlPath string) string {
	switch dbType {
	case "mysql":
		return "mysql"
	case "oracle":
		return "sqlplus"
	case "dameng":
		return "disql"
	case "postgresql":
		return "psql"
	case "mssql":
		return "sqlcmd"
	default: // yashandb
		if yasqlPath != "" {
			return yasqlPath
		}
		return "yasql"
	}
}

// WrapRemoteCmd wraps a command for SSH execution on the target OS.
//
//   - Unix:    bash --login -c '<cmd>'  (or 'source && cmd' when sourceCmd is set)
//   - Windows: pass cmd through (OpenSSH already runs commands via cmd.exe /c; do not nest cmd /C)
func WrapRemoteCmd(targetOS, sourceCmd, cmd string) string {
	if targetOS == OSWindows {
		return wrapRemoteWindows(sourceCmd, cmd)
	}
	return wrapRemoteUnix(sourceCmd, cmd)
}

func wrapRemoteWindows(sourceCmd, cmd string) string {
	if sourceCmd != "" {
		bat := sourceEnvFileForWrap(sourceCmd)
		return fmt.Sprintf(`call %s && %s`, quoteWindowsCmdToken(bat), cmd)
	}
	return cmd
}

func wrapRemoteUnix(sourceCmd, cmd string) string {
	inner := cmd
	if sourceCmd != "" {
		inner = fmt.Sprintf("source %s && %s", quoteUnixSourcePath(sourceEnvFileForWrap(sourceCmd)), cmd)
	}
	return fmt.Sprintf("bash --login -c %s", ShellQuoteUnix(inner))
}

// sourceEnvFileForWrap returns the env file path from SourceCmd (bare path or legacy "source ...").
func sourceEnvFileForWrap(sourceCmd string) string {
	s := strings.TrimSpace(sourceCmd)
	if strings.HasPrefix(s, "source ") {
		s = strings.TrimSpace(s[len("source "):])
		s = strings.Trim(s, `"'`)
	}
	return s
}

func quoteUnixSourcePath(path string) string {
	if strings.HasPrefix(path, "$HOME") {
		return `"` + strings.ReplaceAll(path, `"`, `\"`) + `"`
	}
	return ShellQuoteUnix(path)
}

func quoteWindowsCmdToken(s string) string {
	if strings.ContainsAny(s, " \t\"") {
		return `"` + strings.ReplaceAll(s, `"`, `""`) + `"`
	}
	return s
}

// SourceEnvFileCheckCmd returns a remote command that succeeds when the env file exists.
func SourceEnvFileCheckCmd(targetOS, path string) string {
	path = sourceEnvFileForWrap(path)
	if targetOS == OSWindows {
		return fmt.Sprintf(`if exist %s (echo ok)`, quoteWindowsCmdToken(path))
	}
	if strings.HasPrefix(path, "$HOME") {
		return fmt.Sprintf(`test -f %s`, quoteUnixSourcePath(path))
	}
	return "test -f " + ShellQuoteUnix(path)
}

// WrapLocalSourceCmd wraps a local command with a sourceCmd on the given OS.
// Returns (program, args) suitable for exec.CommandContext.
//
//   - Unix:    ("bash", ["-c", "source && cmd"])
//   - Windows: ("cmd",  ["/C", "call bat && cmd"])
func WrapLocalSourceCmd(localOS, sourceCmd, cmd string) (string, []string) {
	if localOS == OSWindows {
		if sourceCmd != "" {
			return "cmd", []string{"/C", fmt.Sprintf("call %s && %s", windowsInnerQuote(sourceCmd), cmd)}
		}
		return "cmd", []string{"/C", cmd}
	}
	// Unix
	if sourceCmd != "" {
		return "bash", []string{"-c", sourceCmd + " && " + cmd}
	}
	return "bash", []string{"-c", cmd}
}

// CheckRemoteCLICmd returns the shell command string to check whether a CLI exists on the remote OS.
//
//   - Unix:    which <cli>
//   - Windows: where <cli>
func CheckRemoteCLICmd(targetOS, cli string) string {
	if targetOS == OSWindows {
		return fmt.Sprintf("where %s", cli)
	}
	return fmt.Sprintf("which %s", cli)
}

// LocalTempPath returns a platform-appropriate local temp file path using os.TempDir().
// Works correctly on both Unix (/tmp) and Windows (C:\Users\...\AppData\Local\Temp).
func LocalTempPath(filename string) string {
	return filepath.Join(os.TempDir(), filename)
}

// ShellQuoteUnix wraps s in single quotes, escaping embedded single quotes.
// Safe for use in Unix bash -c '...'.
func ShellQuoteUnix(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// windowsInnerQuote escapes embedded double-quotes for use inside cmd /C "...".
func windowsInnerQuote(s string) string {
	return strings.ReplaceAll(s, `"`, `""`)
}

// RemoteScriptPaths returns (sftpPath, execPath) for a script on the SSH target.
// On Windows OpenSSH SFTP requires /C:/drive/path; mysql/sqlplus use C:/drive/path.
func RemoteScriptPaths(targetOS, tempDir, filename string) (sftpPath, execPath string) {
	execPath = RemoteExecScriptPath(targetOS, tempDir, filename)
	if targetOS == OSWindows {
		return windowsOpenSSHSFTPPath(execPath), execPath
	}
	dir := strings.TrimSuffix(strings.ReplaceAll(tempDir, `\`, `/`), `/`)
	return dir + "/" + filename, execPath
}

// RemoteExecScriptPath is the path passed to remote DB CLIs (mysql source, psql -f, sqlplus @).
func RemoteExecScriptPath(targetOS, tempDir, filename string) string {
	if targetOS == OSWindows {
		dir := strings.TrimRight(strings.TrimRight(tempDir, `\`), "/")
		return strings.ReplaceAll(dir, `\`, `/`) + "/" + filename
	}
	dir := strings.TrimSuffix(tempDir, "/")
	return dir + "/" + filename
}

// windowsOpenSSHSFTPPath converts C:/Users/... to /C:/Users/... for Windows OpenSSH SFTP.
func windowsOpenSSHSFTPPath(execPath string) string {
	if len(execPath) >= 2 && execPath[1] == ':' {
		return "/" + execPath
	}
	return execPath
}

// SFTPPath joins tempDir and filename into an SFTP upload path for the target OS.
func SFTPPath(targetOS, tempDir, filename string) string {
	sftp, _ := RemoteScriptPaths(targetOS, tempDir, filename)
	return sftp
}

// ParseRemoteTempOutput extracts a directory path from remote command output.
func ParseRemoteTempOutput(targetOS, output string) string {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if len(lines) == 0 {
		return defaultRemoteTempDir(targetOS)
	}
	dir := strings.TrimSpace(lines[0])
	dir = strings.TrimRight(dir, "\r")
	if dir == "" {
		return defaultRemoteTempDir(targetOS)
	}
	return dir
}

func defaultRemoteTempDir(targetOS string) string {
	if targetOS == OSWindows {
		return `C:\Windows\Temp`
	}
	return "/tmp"
}

// UploadFileViaSFTP uploads content to remotePath on the SSH server using SFTP.
// Creates parent directories implicitly via the SFTP client (server must permit).
// The caller is responsible for ensuring the remote directory exists when needed.
func UploadFileViaSFTP(client *ssh.Client, content []byte, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	f, err := sc.Create(remotePath)
	if err != nil {
		return fmt.Errorf("sftp: failed to create remote file %q: %w", remotePath, err)
	}
	defer f.Close()

	if _, err := f.Write(content); err != nil {
		return fmt.Errorf("sftp: failed to write remote file %q: %w", remotePath, err)
	}
	return nil
}

// DeleteFileViaSFTP removes a remote file via SFTP (best-effort cleanup).
func DeleteFileViaSFTP(client *ssh.Client, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	if err := sc.Remove(remotePath); err != nil {
		return fmt.Errorf("sftp: failed to remove remote file %q: %w", remotePath, err)
	}
	return nil
}

// VerifyFileViaSFTP checks that remotePath exists and is non-empty after upload.
func VerifyFileViaSFTP(client *ssh.Client, remotePath string) error {
	sc, err := sftp.NewClient(client)
	if err != nil {
		return fmt.Errorf("sftp: failed to open subsystem: %w", err)
	}
	defer sc.Close()

	info, err := sc.Stat(remotePath)
	if err != nil {
		return fmt.Errorf("sftp: stat %q: %w", remotePath, err)
	}
	if info.IsDir() {
		return fmt.Errorf("sftp: %q is a directory", remotePath)
	}
	if info.Size() == 0 {
		return fmt.Errorf("sftp: %q is empty", remotePath)
	}
	return nil
}

// CopyPublicKeyRemoteCmd returns the remote shell command that installs pubKeyB64
// (standard base64 of the OpenSSH authorized_keys line) on the target OS.
func CopyPublicKeyRemoteCmd(targetOS, pubKeyB64 string) string {
	if targetOS == OSWindows {
		return wrapPowerShellEncoded(copyPublicKeyWindowsScript(pubKeyB64))
	}
	return copyPublicKeyUnixCmd(pubKeyB64)
}

// DeletePublicKeyRemoteCmd returns the remote shell command that removes pubKeyB64
// from authorized_keys on the target OS.
func DeletePublicKeyRemoteCmd(targetOS, pubKeyB64 string) string {
	if targetOS == OSWindows {
		return wrapPowerShellEncoded(deletePublicKeyWindowsScript(pubKeyB64))
	}
	return deletePublicKeyUnixCmd(pubKeyB64)
}

func copyPublicKeyUnixCmd(pubKeyB64 string) string {
	return fmt.Sprintf(
		"mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '%s' | base64 -d >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys",
		pubKeyB64,
	)
}

func deletePublicKeyUnixCmd(pubKeyB64 string) string {
	return fmt.Sprintf(
		"grep -vF \"$(echo '%s' | base64 -d)\" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp || true; mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys",
		pubKeyB64,
	)
}

func copyPublicKeyWindowsScript(pubKeyB64 string) string {
	return fmt.Sprintf(`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')).Trim();$isAdmin=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);if($isAdmin){New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ssh'|Out-Null;$f='C:\ProgramData\ssh\administrators_authorized_keys'}else{$d=Join-Path $env:USERPROFILE '.ssh';New-Item -ItemType Directory -Force -Path $d|Out-Null;$f=Join-Path $d 'authorized_keys'};$enc=New-Object Text.UTF8Encoding $false;if((Test-Path $f)-and(Select-String -Path $f -Pattern ([regex]::Escape($k)) -SimpleMatch -Quiet)){'KEY_EXISTS'}else{if(Test-Path $f){$lines=[IO.File]::ReadAllLines($f)|Where-Object{$_.Trim()-ne ''};if($lines -notcontains $k){$lines+=$k};[IO.File]::WriteAllLines($f,$lines,$enc)}else{[IO.File]::WriteAllText($f,$k+[Environment]::NewLine,$enc)};if($isAdmin){$acl=Get-Acl $f;$acl.SetAccessRuleProtection($true,$false);$acl.Access|ForEach-Object{$null=$acl.RemoveAccessRule($_)};$null=$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','Allow')));$null=$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','Allow')));Set-Acl $f $acl}else{$sshDir=Split-Path $f -Parent;$grant=$env:USERNAME+':(F)';icacls $sshDir /inheritance:r /grant:r $grant 'SYSTEM:(F)'|Out-Null;icacls $f /inheritance:r /grant:r $grant 'SYSTEM:(F)'|Out-Null};'KEY_ADDED'}`,
		pubKeyB64,
	)
}

func deletePublicKeyWindowsScript(pubKeyB64 string) string {
	return fmt.Sprintf(`$k=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')).Trim();$isAdmin=(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);if($isAdmin){$f='C:\ProgramData\ssh\administrators_authorized_keys'}else{$f=Join-Path (Join-Path $env:USERPROFILE '.ssh') 'authorized_keys'};if(-not(Test-Path $f)){'KEY_NOT_FOUND';return};$enc=New-Object Text.UTF8Encoding $false;$lines=@([IO.File]::ReadAllLines($f)|Where-Object{$_.Trim()-ne $k -and $_.Trim()-ne ''});[IO.File]::WriteAllLines($f,$lines,$enc);'KEY_REMOVED'`,
		pubKeyB64,
	)
}

func wrapPowerShellEncoded(script string) string {
	return "powershell -NoProfile -EncodedCommand " + encodePowerShellCommand(script)
}

func encodePowerShellCommand(script string) string {
	u16 := utf16.Encode([]rune(script))
	buf := make([]byte, len(u16)*2)
	for i, r := range u16 {
		buf[i*2] = byte(r)
		buf[i*2+1] = byte(r >> 8)
	}
	return base64.StdEncoding.EncodeToString(buf)
}

// IsWindowsTarget reports whether targetOS selects Windows remote commands.
func IsWindowsTarget(targetOS string) bool {
	return strings.EqualFold(targetOS, OSWindows)
}

// OS type constants used throughout the codebase.
const (
	OSUnix    = "unix"
	OSWindows = "windows"
)

// LocalOS returns the OS of the machine where ytop is currently running.
func LocalOS() string {
	if runtime.GOOS == "windows" {
		return OSWindows
	}
	return OSUnix
}

// DetectRemoteOS probes the remote host OS via an existing SSH client.
// Returns OSWindows or OSUnix. Always falls back to OSUnix on any error or timeout.
// debugLog may be nil.
func DetectRemoteOS(ctx context.Context, client *ssh.Client, debugLog func(string, ...interface{})) string {
	if debugLog != nil {
		debugLog("[platform] detecting remote OS via SSH probe\n")
	}

	type probeResult struct {
		os  string
		err error
	}
	done := make(chan probeResult, 1)

	go func() {
		os, err := probeRemoteOS(client)
		done <- probeResult{os, err}
	}()

	probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	select {
	case <-probeCtx.Done():
		if debugLog != nil {
			debugLog("[platform] remote OS probe timed out (5s); defaulting to unix\n")
		}
		return OSUnix
	case r := <-done:
		if r.err != nil {
			if debugLog != nil {
				debugLog("[platform] remote OS probe error: %v; defaulting to unix\n", r.err)
			}
			return OSUnix
		}
		if debugLog != nil {
			debugLog("[platform] remote OS detected: %s\n", r.os)
		}
		return r.os
	}
}

// probeRemoteOS runs `cmd /C echo PROBE_WIN` over SSH.
// Windows OpenSSH runs this in cmd.exe and returns "PROBE_WIN" with exit 0.
// On Unix, `cmd` is not found and the session exits non-zero.
func probeRemoteOS(client *ssh.Client) (string, error) {
	session, err := client.NewSession()
	if err != nil {
		return OSUnix, err
	}
	defer session.Close()

	out, err := session.CombinedOutput(`cmd /C "echo PROBE_WIN"`)
	if err == nil && strings.Contains(string(out), "PROBE_WIN") {
		return OSWindows, nil
	}
	return OSUnix, nil
}

const (
	mssqlProbeSQLCmdPrefix = "YTOP_SQLCMD="
	mssqlProbePortPrefix   = "YTOP_MSSQL_PORT="
)

// BuildWindowsMssqlRegistryProbeCmd returns a PowerShell command that locates sqlcmd.exe
// and the default instance TCP port via SQL Server registry keys.
func BuildWindowsMssqlRegistryProbeCmd() string {
	return wrapPowerShellEncoded(windowsMssqlRegistryProbeScript())
}

func windowsMssqlRegistryProbeScript() string {
	return `$ErrorActionPreference='SilentlyContinue'
$ProgressPreference='SilentlyContinue'
$sqlcmd=$null
function Resolve-SqlcmdFromRegPath([string]$binPath) {
  if(-not $binPath){ return $null }
  $c=Join-Path $binPath 'sqlcmd.exe'
  if(Test-Path -LiteralPath $c){ return $c }
  return $null
}
function Resolve-SqlcmdFromVersion([string]$ver) {
  if(-not $ver){ return $null }
  $sdk=Join-Path $env:ProgramFiles ("Microsoft SQL Server\Client SDK\ODBC\{0}\Tools\Binn\sqlcmd.exe" -f $ver)
  if(Test-Path -LiteralPath $sdk){ return $sdk }
  return $null
}
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Client SDK\ODBC' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
  if($sqlcmd){ return }
  foreach($sub in @('Tools\ClientSetup','Tools\Setup')) {
    $p=(Get-ItemProperty (Join-Path $_.PSPath $sub) -Name Path -ErrorAction SilentlyContinue).Path
    $c=Resolve-SqlcmdFromRegPath $p
    if($c){ $script:sqlcmd=$c; break }
  }
}
if(-not $sqlcmd){
  $verKeys=@(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d+$' } | Sort-Object { [int]$_.PSChildName } -Descending)
  foreach($key in $verKeys){
    if($sqlcmd){ break }
    $ver=$key.PSChildName
    $p=(Get-ItemProperty (Join-Path $key.PSPath 'Tools\ClientSetup') -Name Path -ErrorAction SilentlyContinue).Path
    $c=Resolve-SqlcmdFromRegPath $p
    if(-not $c){ $c=Resolve-SqlcmdFromVersion $ver }
    if($c){ $script:sqlcmd=$c; break }
  }
}
if(-not $sqlcmd){
  $root=Join-Path $env:ProgramFiles 'Microsoft SQL Server'
  if(Test-Path -LiteralPath $root){
    $found=Get-ChildItem -LiteralPath $root -Recurse -Filter sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if($found){ $script:sqlcmd=$found.FullName }
  }
}
$port=''
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'MSSQL*.MSSQLSERVER' } | Select-Object -First 1 | ForEach-Object {
  $ip=Join-Path $_.PSPath 'MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
  if(Test-Path -LiteralPath $ip){ $port=(Get-ItemProperty -LiteralPath $ip -Name TcpPort -ErrorAction SilentlyContinue).TcpPort }
}
Write-Output ('YTOP_SQLCMD='+$sqlcmd)
Write-Output ('YTOP_MSSQL_PORT='+$port)
`
}

// ParseWindowsMssqlRegistryProbeOutput parses probe stdout lines.
func ParseWindowsMssqlRegistryProbeOutput(output string) (sqlcmdPath, tcpPort string, err error) {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(strings.TrimRight(line, "\r"))
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, mssqlProbeSQLCmdPrefix) {
			sqlcmdPath = strings.TrimSpace(strings.TrimPrefix(line, mssqlProbeSQLCmdPrefix))
			continue
		}
		if strings.HasPrefix(line, mssqlProbePortPrefix) {
			tcpPort = strings.TrimSpace(strings.TrimPrefix(line, mssqlProbePortPrefix))
		}
	}
	if sqlcmdPath == "" {
		return "", tcpPort, fmt.Errorf("sqlcmd path not found in registry probe output")
	}
	return sqlcmdPath, tcpPort, nil
}

// OSScriptKind identifies how an OS script should be executed.
type OSScriptKind int

const (
	OSScriptKindUnknown OSScriptKind = iota
	OSScriptKindBash
	OSScriptKindPowerShell
	OSScriptKindCmd
	OSScriptKindPython
)

// OSScriptKindFromExt returns the runner kind for a script filename extension.
func OSScriptKindFromExt(filename string) OSScriptKind {
	switch strings.ToLower(filepath.Ext(filename)) {
	case ".sh", ".bash", ".zsh", ".ksh":
		return OSScriptKindBash
	case ".ps1":
		return OSScriptKindPowerShell
	case ".bat", ".cmd":
		return OSScriptKindCmd
	case ".py":
		return OSScriptKindPython
	default:
		return OSScriptKindUnknown
	}
}

// OSScriptSupportedOn reports whether kind can run on targetOS.
func OSScriptSupportedOn(kind OSScriptKind, targetOS string) bool {
	switch kind {
	case OSScriptKindBash:
		return targetOS == OSUnix
	case OSScriptKindPowerShell, OSScriptKindCmd:
		return targetOS == OSWindows
	case OSScriptKindPython:
		return true
	default:
		return targetOS == OSUnix
	}
}

// OSScriptMismatchError returns an error when script kind does not match target OS.
func OSScriptMismatchError(scriptName, targetOS string, kind OSScriptKind) error {
	switch kind {
	case OSScriptKindBash:
		return fmt.Errorf("script %s requires unix target (detected %s)", scriptName, targetOS)
	case OSScriptKindPowerShell, OSScriptKindCmd:
		return fmt.Errorf("script %s requires windows target (detected %s)", scriptName, targetOS)
	default:
		if targetOS == OSWindows {
			return fmt.Errorf("script %s is not supported on windows target", scriptName)
		}
		return fmt.Errorf("script %s is not supported on unix target", scriptName)
	}
}

// DefaultPythonBin returns the default Python interpreter name for targetOS.
func DefaultPythonBin(targetOS string) string {
	if targetOS == OSWindows {
		return "python"
	}
	return "python3"
}

// BuildOSScriptRunCmd builds a shell command to run scriptPath with optional args.
func BuildOSScriptRunCmd(targetOS, scriptPath string, args []string, kind OSScriptKind, pythonBin string) (string, error) {
	if pythonBin == "" {
		pythonBin = DefaultPythonBin(targetOS)
	}

	switch kind {
	case OSScriptKindBash:
		return buildBashScriptCmd(targetOS, scriptPath, args), nil
	case OSScriptKindPowerShell:
		return buildPowerShellScriptCmd(scriptPath, args), nil
	case OSScriptKindCmd:
		return buildCmdScriptCmd(scriptPath, args), nil
	case OSScriptKindPython:
		return buildPythonScriptCmd(targetOS, scriptPath, args, pythonBin), nil
	default:
		if targetOS == OSWindows {
			return buildCmdScriptCmd(scriptPath, args), nil
		}
		return buildBashScriptCmd(targetOS, scriptPath, args), nil
	}
}

func buildBashScriptCmd(targetOS, scriptPath string, args []string) string {
	path := scriptPath
	if targetOS == OSWindows {
		path = strings.ReplaceAll(scriptPath, `\`, `/`)
	} else {
		path = ShellQuoteUnix(scriptPath)
	}
	cmd := "bash " + path
	if len(args) > 0 {
		cmd += " " + shellJoinUnixArgs(args)
	}
	return cmd
}

func buildPowerShellScriptCmd(scriptPath string, args []string) string {
	path := quoteWindowsScriptPath(scriptPath)
	cmd := "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + path
	if len(args) > 0 {
		cmd += " " + shellJoinWindowsArgs(args)
	}
	return cmd
}

func buildCmdScriptCmd(scriptPath string, args []string) string {
	path := quoteWindowsScriptPath(scriptPath)
	cmd := "call " + path
	if len(args) > 0 {
		cmd += " " + shellJoinWindowsArgs(args)
	}
	return cmd
}

func buildPythonScriptCmd(targetOS, scriptPath string, args []string, pythonBin string) string {
	if targetOS == OSWindows {
		path := quoteWindowsScriptPath(scriptPath)
		cmd := quoteWindowsScriptPath(pythonBin) + " -u " + path
		if len(args) > 0 {
			cmd += " " + shellJoinWindowsArgs(args)
		}
		return cmd
	}
	path := ShellQuoteUnix(scriptPath)
	py := ShellQuoteUnix(pythonBin)
	cmd := py + " -u " + path
	if len(args) > 0 {
		cmd += " " + shellJoinUnixArgs(args)
	}
	return cmd
}

func quoteWindowsScriptPath(path string) string {
	path = strings.ReplaceAll(path, `/`, `\`)
	if strings.ContainsAny(path, " \t\"") {
		return `"` + strings.ReplaceAll(path, `"`, `""`) + `"`
	}
	return path
}

func shellJoinUnixArgs(args []string) string {
	parts := make([]string, len(args))
	for i, a := range args {
		parts[i] = ShellQuoteUnix(a)
	}
	return strings.Join(parts, " ")
}

func shellJoinWindowsArgs(args []string) string {
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

// DefaultScriptCopyDir returns the default destination directory for --copy.
func DefaultScriptCopyDir(targetOS string) string {
	return defaultRemoteTempDir(targetOS)
}
