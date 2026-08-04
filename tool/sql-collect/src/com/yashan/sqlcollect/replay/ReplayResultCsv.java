package com.yashan.sqlcollect.replay;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/** 结构化回放结果 CSV (线程安全追加) */
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
