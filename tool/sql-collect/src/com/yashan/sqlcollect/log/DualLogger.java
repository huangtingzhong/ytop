package com.yashan.sqlcollect.log;

import com.yashan.sqlcollect.Version;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.atomic.AtomicLong;

/** 双文件日志: session + debug; 对齐 Python DualLogger 细节 (STEP/command_result/banner) */
public class DualLogger implements AutoCloseable {

    private static final String LINE_TS = "yyyy-MM-dd HH:mm:ss";
    private static final int LEVEL_WIDTH = 5;
    private static final AtomicLong RUN_SEQ = new AtomicLong(0);

    private final BufferedWriter session;
    private final BufferedWriter debug;
    private final PrintStream out;
    private final PrintStream err;
    private final SimpleDateFormat tsFmt = new SimpleDateFormat(LINE_TS, Locale.US);
    private final String runId;
    private final String command;
    private final Path sessionPath;
    private final Path debugPath;
    private final boolean debugEnabled;

    public DualLogger(Path logDir, String command) throws IOException {
        this(logDir, command, true);
    }

    public DualLogger(Path logDir, String command, boolean debugEnabled) throws IOException {
        Files.createDirectories(logDir);
        String stamp = new SimpleDateFormat("yyyyMMddHHmmss", Locale.US).format(new Date());
        this.command = command == null ? "main" : command;
        this.debugEnabled = debugEnabled;
        this.runId = stamp + "-" + RUN_SEQ.incrementAndGet();
        this.sessionPath = logDir.resolve("sql_collect_" + this.command + "_" + stamp + ".log");
        this.debugPath = logDir.resolve("sql_collect_" + this.command + "_debug_" + stamp + ".log");
        this.session = Files.newBufferedWriter(sessionPath, StandardCharsets.UTF_8);
        this.debug = Files.newBufferedWriter(debugPath, StandardCharsets.UTF_8);
        this.out = System.out;
        this.err = System.err;
        writeBanner();
        logDbg("logger init run_id=" + runId + " cmd=" + this.command + " debug=" + debugEnabled);
    }

    public boolean isDebugEnabled() {
        return debugEnabled;
    }

    public Path getSessionPath() {
        return sessionPath;
    }

    public Path getDebugPath() {
        return debugPath;
    }

    private void writeBanner() {
        String banner = "Version: " + Version.VERSION + "\n"
                + "Author: huangtingzhong\n"
                + "Contact: -\n\n"
                + "The log of current session can be found at:\n  " + sessionPath.toAbsolutePath() + "\n"
                + (debugEnabled
                ? ("Debug log can be found at:\n  " + debugPath.toAbsolutePath() + "\n")
                : "Debug log: disabled (--debug false)\n");
        out.print(banner);
        out.flush();
        try {
            session.write(banner);
            session.flush();
            for (String ln : banner.split("\n", -1)) {
                if (ln.trim().isEmpty()) {
                    continue;
                }
                debug.write(formatLine("INFO", ln));
                debug.newLine();
            }
            debug.flush();
        } catch (IOException ignored) {
        }
    }

    public void logInfo(String msg) {
        write("INFO", msg, true, false);
    }

    public void logWarn(String msg) {
        write("WARN", msg, true, false);
    }

    public void logError(String msg) {
        write("ERROR", msg, true, true);
    }

    public void logDbg(String msg) {
        if (!debugEnabled) {
            return;
        }
        writeDebugOnly("DEBUG", msg);
    }

    public void logStep(String step, String detail) {
        if (!debugEnabled) {
            return;
        }
        String body;
        if (detail == null || detail.isEmpty()) {
            body = "=== [STEP] " + step + " ===";
        } else {
            body = "=== [STEP] " + step + ": " + detail + " ===";
        }
        writeDebugOnly("STEP", body);
    }

    /**
     * 记录一次 JDBC/命令结果到 debug (及可选 session).
     * 格式对齐 Python command_result.
     */
    public void commandResult(String scope, String cmd, int rc, String output, double durationSec) {
        StringBuilder sb = new StringBuilder();
        sb.append("command_result scope=").append(scope)
                .append(" rc=").append(rc)
                .append(" duration_sec=").append(String.format(Locale.US, "%.3f", durationSec))
                .append(" cmd=").append(cmd == null ? "" : cmd);
        logDbg(sb.toString());
        if (output != null && !output.isEmpty()) {
            String[] lines = output.split("\n", -1);
            int limit = Math.min(lines.length, 80);
            for (int i = 0; i < limit; i++) {
                logDbg("  out|" + lines[i]);
            }
            if (lines.length > limit) {
                logDbg("  out|... (" + (lines.length - limit) + " more lines)");
            }
        }
    }

    /**
     * replay 过程明细: 写入 session + debug, 不刷终端 (终端由 ReplayCommand 一行摘要).
     */
    public synchronized void logReplayLine(String line) {
        if (line == null) {
            return;
        }
        try {
            String ln = formatLine("INFO", line);
            session.write(ln);
            session.newLine();
            session.flush();
            if (debugEnabled) {
                debug.write(ln);
                debug.newLine();
                debug.flush();
            }
        } catch (IOException ignored) {
        }
    }

    private String formatLine(String level, String msg) {
        String ts = tsFmt.format(new Date());
        String padded = String.format(Locale.US, "%-" + LEVEL_WIDTH + "s", level);
        return ts + "  " + padded + "  " + msg;
    }

    /** DEBUG/STEP 仅写 debug 文件, 避免大段 SQL/bind 撑爆 session */
    private synchronized void writeDebugOnly(String level, String msg) {
        try {
            String ln = formatLine(level, msg);
            debug.write(ln);
            debug.newLine();
            debug.flush();
        } catch (IOException ignored) {
        }
    }

    /**
     * 终端可见日志 (INFO/WARN/ERROR): 同时写 session + debug + stdout/stderr.
     * DEBUG/STEP: 仅 debug 文件 (见 {@link #logDbg}/{@link #logStep}).
     */
    private synchronized void write(String level, String msg, boolean mirrorStdout, boolean toStderr) {
        try {
            String ln = formatLine(level, msg);
            session.write(ln);
            session.newLine();
            session.flush();
            // 终端行始终镜像进 debug, 便于单文件完整回放跟踪
            if (debugEnabled) {
                debug.write(ln);
                debug.newLine();
                debug.flush();
            }
            if (mirrorStdout) {
                // 与 session 文件一致: 时间戳 + 级别 + 正文
                if (toStderr) {
                    err.println(ln);
                } else {
                    out.println(ln);
                }
            }
        } catch (IOException e) {
            if (mirrorStdout) {
                String fallback = formatLine(level, msg);
                (toStderr ? err : out).println(fallback);
            }
        }
    }

    @Override
    public synchronized void close() {
        try {
            session.close();
        } catch (IOException ignored) {
        }
        try {
            debug.close();
        } catch (IOException ignored) {
        }
    }
}
