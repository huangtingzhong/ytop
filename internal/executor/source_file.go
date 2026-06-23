package executor

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/yihan/ytop/internal/config"
	"github.com/yihan/ytop/internal/connector"
	"github.com/yihan/ytop/internal/logger"
	"github.com/yihan/ytop/internal/platform"
	"github.com/yihan/ytop/internal/scripts"
	"github.com/yihan/ytop/internal/utils"
)

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
