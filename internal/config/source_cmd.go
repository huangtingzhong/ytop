package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// FinalizeSourceCmd normalizes -s / source_cmd for a single env file path (no spaces).
// Non-absolute paths are under the login user's $HOME (SSH) or local home (local).
// If the user omitted quotes and the shell expanded ~ to the local home directory, the path
// is rewritten to $HOME/... on the remote.
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
		resolved := normalizeSSHSourcePath(raw, homeSlash)
		src, probe := formatSSHSourceAndProbe(resolved)
		cfg.SourceCmd = src
		cfg.SSHSourceExistenceCheck = probe
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

func normalizeSSHSourcePath(path, homeSlash string) string {
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
	if strings.HasPrefix(path, "~/") {
		rest := strings.TrimPrefix(path, "~/")
		if rest == "" {
			return "$HOME"
		}
		return "$HOME/" + rest
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

func formatLocalSource(resolved string) string {
	return "source " + shellSingleQuote(filepath.ToSlash(resolved))
}

// formatSSHSourceAndProbe returns the source line and a one-shot remote check: `test -f <path>`.
func formatSSHSourceAndProbe(resolved string) (sourceLine, testCmd string) {
	q := shellWordForSSHPath(resolved)
	return "source " + q, "test -f " + q
}

func shellWordForSSHPath(resolved string) string {
	if strings.HasPrefix(resolved, "$HOME") {
		return shellDoubleQuote(resolved)
	}
	if strings.HasPrefix(resolved, "/") {
		return shellSingleQuote(resolved)
	}
	// should not happen
	return shellSingleQuote(resolved)
}

func shellSingleQuote(s string) string {
	return `'` + strings.ReplaceAll(s, `'`, `'\''`) + `'`
}

func shellDoubleQuote(s string) string {
	return `"` + strings.ReplaceAll(s, `"`, `\"`) + `"`
}
