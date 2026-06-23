package platform

import (
	"fmt"
	"path/filepath"
	"strings"
)

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
