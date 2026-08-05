package com.yashan.sqlcollect.replay;

import com.yashan.sqlcollect.util.RunDirResolver;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** 结构化回放结果 CSV (线程安全追加); 支持成功键加载与 --replay-all 备份 */
public final class ReplayResultCsv {

    public static final String HEADER =
            "sql_id,child,inst_id,schema,kind,rc,elapsed_ms,rows_or_updatecount,error_class,ts";

    private final Path path;
    private final Object lock = new Object();

    public ReplayResultCsv(Path path) throws IOException {
        this.path = path.toAbsolutePath().normalize();
        Path parent = this.path.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        if (!Files.isRegularFile(this.path)) {
            Files.write(this.path, (HEADER + "\n").getBytes(StandardCharsets.UTF_8));
        }
    }

    public Path path() {
        return path;
    }

    public void append(String sqlId, int child, int instId, String schema, String kind,
                       int rc, long elapsedMs, String rowsOrUpdate, String errorClass) {
        String ts = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(new Date());
        String line = csv(sqlId) + "," + child + "," + instId + ","
                + csv(schema) + "," + csv(kind) + "," + rc + "," + elapsedMs + ","
                + csv(rowsOrUpdate) + "," + csv(errorClass) + "," + csv(ts);
        synchronized (lock) {
            try {
                Files.write(path, (line + "\n").getBytes(StandardCharsets.UTF_8),
                        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException e) {
                System.err.println("WARN: write replay_results.csv failed: " + e.getMessage());
            }
        }
    }

    /** 复合键 sql_id|child|inst_id */
    public static String key(String sqlId, int child, int instId) {
        return (sqlId == null ? "" : sqlId) + "|" + child + "|" + instId;
    }

    /**
     * 加载已成功 LIVE 执行 (rc=0) 的键.
     * CSV 的 kind 列为 SQL 分类 (query/dml/plsql/...); dry-run 成功行以
     * rows_or_updatecount=dry 或 error_class=blocked_dry 标记, 不计入,
     * 以免阻断后续 --exec.
     */
    public Set<String> loadOkExecKeys() throws IOException {
        return loadOkExecKeys(path);
    }

    public static Set<String> loadOkExecKeys(Path csvPath) throws IOException {
        Set<String> out = new HashSet<String>();
        if (csvPath == null || !Files.isRegularFile(csvPath)) {
            return out;
        }
        List<String> lines = Files.readAllLines(csvPath, StandardCharsets.UTF_8);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (line == null) {
                continue;
            }
            line = line.trim();
            if (line.isEmpty() || line.startsWith("sql_id,")) {
                continue;
            }
            String[] p = splitCsvLine(line);
            if (p.length < 6) {
                continue;
            }
            String sid = p[0];
            int child = parseIntSafe(p[1], 0);
            int inst = parseIntSafe(p[2], 1);
            int rc = parseIntSafe(p[5], -1);
            if (rc != 0) {
                continue;
            }
            String rowsOrUc = p.length > 7 ? p[7] : "";
            String err = p.length > 8 ? p[8] : "";
            if (isDryRunSuccess(rowsOrUc, err)) {
                continue;
            }
            out.add(key(sid, child, inst));
        }
        return out;
    }

    /** dry-run 成功行: 不参与增量跳过 */
    static boolean isDryRunSuccess(String rowsOrUc, String errorClass) {
        if (rowsOrUc != null && "dry".equalsIgnoreCase(rowsOrUc.trim())) {
            return true;
        }
        return errorClass != null && "blocked_dry".equalsIgnoreCase(errorClass.trim());
    }

    /** 是否存在该 sql_id 的任意成功 exec 记录 */
    public static boolean hasOkExecForSqlId(Set<String> okKeys, String sqlId) {
        if (okKeys == null || okKeys.isEmpty() || sqlId == null) {
            return false;
        }
        String prefix = sqlId + "|";
        for (String k : okKeys) {
            if (k != null && k.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    /**
     * 备份现有 CSV 到同目录 (replay_results.csv.&lt;yyyyMMddHHmmss&gt;), 再写新空表头.
     * @return 备份路径; 若原文件不存在则返回 null
     */
    public Path backupAndReset() throws IOException {
        synchronized (lock) {
            Path bak = null;
            if (Files.isRegularFile(path)) {
                String stamp = RunDirResolver.nowStamp();
                bak = path.resolveSibling(path.getFileName().toString() + "." + stamp);
                Files.copy(path, bak, StandardCopyOption.REPLACE_EXISTING);
            }
            Files.write(path, (HEADER + "\n").getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
            return bak;
        }
    }

    static String[] splitCsvLine(String line) {
        // 简单 CSV: 支持引号字段
        java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
        StringBuilder cur = new StringBuilder();
        boolean inQ = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (inQ) {
                if (c == '"') {
                    if (i + 1 < line.length() && line.charAt(i + 1) == '"') {
                        cur.append('"');
                        i++;
                    } else {
                        inQ = false;
                    }
                } else {
                    cur.append(c);
                }
            } else if (c == '"') {
                inQ = true;
            } else if (c == ',') {
                parts.add(cur.toString());
                cur.setLength(0);
            } else {
                cur.append(c);
            }
        }
        parts.add(cur.toString());
        return parts.toArray(new String[parts.size()]);
    }

    private static int parseIntSafe(String s, int def) {
        if (s == null || s.trim().isEmpty()) {
            return def;
        }
        try {
            return Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static String csv(String s) {
        if (s == null) {
            return "";
        }
        boolean needQuote = s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0
                || s.indexOf('\r') >= 0;
        String v = s.replace("\"", "\"\"");
        return needQuote ? "\"" + v + "\"" : v;
    }
}
