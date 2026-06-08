package platform

import "strings"

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
