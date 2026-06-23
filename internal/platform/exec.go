package platform

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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
