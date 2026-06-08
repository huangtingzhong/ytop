package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const winUserProfileVar = "%USERPROFILE%"

// FinalizeSourceCmd normalizes -s / source_cmd for a single env file path (no spaces).
// Non-absolute paths are under the login user's $HOME (SSH Unix) or %USERPROFILE% (SSH/local Windows).
// If the user omitted quotes and the shell expanded ~ to the local home directory, the path
// is rewritten to $HOME/... on Unix or %USERPROFILE%\... on Windows.
// Custom shell snippets (contain spaces, or start with "source ") are left unchanged.
// For local simple paths, the file must exist (os.Stat). For SSH, the caller should run
// SSHSourceExistenceCheck on the remote during Connect.
func FinalizeSourceCmd(cfg *Config) error {
	cfg.SSHSourceExistenceCheck = ""
	if cfg.SourceCmd == "" {
		return nil
	}
	raw := strings.TrimSpace(cfg.SourceCmd)
	// Full shell command: do not interpret as a bare file path
	if strings.Contains(raw, " ") || strings.HasPrefix(raw, "source ") {
		return nil
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("user home directory: %w", err)
	}
	homeSlash := filepath.ToSlash(home)

	if cfg.ConnectionMode == "ssh" {
		resolved := normalizeSSHSourcePath(raw, homeSlash, cfg.TargetOS)
		cfg.SourceCmd = resolved
		cfg.SSHSourceExistenceCheck = resolved
		return nil
	}

	if isWindowsTarget(cfg) {
		resolved, err := normalizeWindowsLocalSourcePath(raw, home)
		if err != nil {
			return err
		}
		if _, err := os.Stat(resolved); err != nil {
			return fmt.Errorf("source file not found: %s: %w", resolved, err)
		}
		cfg.SourceCmd = resolved
		return nil
	}

	resolved, err := normalizeLocalSourcePath(raw, home)
	if err != nil {
		return err
	}
	if _, err := os.Stat(resolved); err != nil {
		return fmt.Errorf("source file not found: %s: %w", resolved, err)
	}
	cfg.SourceCmd = formatLocalSource(resolved)
	return nil
}

// AdaptSourceCmdForWindowsSSH rewrites Unix-style -s paths after SSH target OS is detected as Windows.
// Converts $HOME/... to %USERPROFILE%\... and forward slashes to backslashes.
func AdaptSourceCmdForWindowsSSH(cfg *Config) {
	if cfg == nil || cfg.SourceCmd == "" || cfg.TargetOS != "windows" {
		return
	}
	raw := strings.TrimSpace(cfg.SourceCmd)
	if strings.Contains(raw, " ") || strings.HasPrefix(raw, "source ") {
		return
	}
	adapted := toWindowsRemoteSourcePath(raw)
	cfg.SourceCmd = adapted
	cfg.SSHSourceExistenceCheck = adapted
}

func isWindowsTarget(cfg *Config) bool {
	if cfg.TargetOS == "windows" {
		return true
	}
	return cfg.ConnectionMode == "local" && isLocalWindows()
}

func normalizeLocalSourcePath(path, home string) (string, error) {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	if strings.HasPrefix(path, "~/") {
		return filepath.Clean(filepath.Join(home, path[2:])), nil
	}
	if filepath.IsAbs(path) {
		return filepath.Clean(path), nil
	}
	path = strings.TrimPrefix(path, "./")
	return filepath.Clean(filepath.Join(home, path)), nil
}

func normalizeWindowsLocalSourcePath(path, home string) (string, error) {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	if path == "~" {
		return home, nil
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Clean(filepath.Join(home, path[2:])), nil
	}
	if isWindowsDrivePath(path) {
		return toWindowsNativePath(path), nil
	}
	if filepath.IsAbs(path) {
		return toWindowsNativePath(path), nil
	}
	path = strings.TrimPrefix(path, "./")
	return filepath.Clean(filepath.Join(home, path)), nil
}

func normalizeSSHSourcePath(path, homeSlash, targetOS string) string {
	if targetOS == "windows" {
		return normalizeWindowsSSHSourcePath(path, homeSlash)
	}
	return normalizeUnixSSHSourcePath(path, homeSlash)
}

func normalizeUnixSSHSourcePath(path, homeSlash string) string {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	// Local shell expanded ~ to the control machine's home; map to remote $HOME
	if homeSlash != "" {
		if path == homeSlash {
			return "$HOME"
		}
		prefix := homeSlash + "/"
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			if rest == "" {
				return "$HOME"
			}
			return "$HOME/" + rest
		}
	}
	if path == "~" {
		return "$HOME"
	}
	if strings.HasPrefix(path, "~/") {
		rest := strings.TrimPrefix(path, "~/")
		if rest == "" {
			return "$HOME"
		}
		return "$HOME/" + rest
	}
	if isWindowsDrivePath(path) {
		return path
	}
	if strings.HasPrefix(path, "/") {
		return path
	}
	path = strings.TrimPrefix(path, "./")
	if path == "" || path == "." {
		return "$HOME"
	}
	return "$HOME/" + path
}

func normalizeWindowsSSHSourcePath(path, homeSlash string) string {
	path = strings.TrimSpace(path)
	path = filepath.ToSlash(path)
	// Control machine shell expanded ~ to local home; map to remote %USERPROFILE%
	if homeSlash != "" {
		if path == homeSlash {
			return winUserProfileVar
		}
		prefix := homeSlash + "/"
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			return joinWindowsRemoteProfile(rest)
		}
	}
	if path == "~" {
		return winUserProfileVar
	}
	if strings.HasPrefix(path, "~/") {
		rest := strings.TrimPrefix(path, "~/")
		return joinWindowsRemoteProfile(rest)
	}
	if isWindowsDrivePath(path) {
		return toWindowsNativePath(path)
	}
	if strings.HasPrefix(path, "/") {
		return toWindowsNativePath(path)
	}
	path = strings.TrimPrefix(path, "./")
	if path == "" || path == "." {
		return winUserProfileVar
	}
	return joinWindowsRemoteProfile(path)
}

func toWindowsRemoteSourcePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "$HOME" {
		return winUserProfileVar
	}
	if strings.HasPrefix(path, "$HOME/") {
		return joinWindowsRemoteProfile(strings.TrimPrefix(path, "$HOME/"))
	}
	if strings.Contains(path, "/") {
		return toWindowsNativePath(path)
	}
	return path
}

func joinWindowsRemoteProfile(rest string) string {
	rest = strings.TrimSpace(rest)
	rest = strings.TrimPrefix(rest, "./")
	if rest == "" || rest == "." {
		return winUserProfileVar
	}
	return winUserProfileVar + "\\" + strings.ReplaceAll(rest, "/", "\\")
}

func toWindowsNativePath(path string) string {
	return strings.ReplaceAll(path, "/", "\\")
}

func isWindowsDrivePath(path string) bool {
	return len(path) >= 2 && path[1] == ':'
}

func formatLocalSource(resolved string) string {
	return "source " + shellSingleQuote(filepath.ToSlash(resolved))
}

func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}
