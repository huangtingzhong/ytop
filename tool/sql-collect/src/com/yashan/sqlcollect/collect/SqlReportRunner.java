package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.log.DualLogger;

import java.io.IOException;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

/**
 * JDBC 执行报告 SELECT 段 ({@link ReportSelectScript}: PLAN / sqlarea / AWR / objects).
 * ORIGINAL/LITERAL 由 {@link JdbcReportBuilder} 纯 Java 写出.
 */
public class SqlReportRunner {

    private final DualLogger log;

    public SqlReportRunner(DualLogger log) {
        this.log = log;
    }

    static String substituteSqlId(String template, String sqlId) {
        String safe = sqlId == null ? "" : sqlId.replace("'", "''");
        String s = template.replace("&&sqlid", safe);
        s = s.replace("&sqlid", safe);
        return s;
    }

    static String loadTemplate() {
        return ReportSelectScript.content();
    }

    private static int remainingQueryTimeoutSec(long deadlineMs, int overallTimeoutSec) {
        if (overallTimeoutSec <= 0) {
            return 0;
        }
        long leftMs = deadlineMs - System.currentTimeMillis();
        if (leftMs <= 0) {
            return 1;
        }
        int leftSec = (int) ((leftMs + 999L) / 1000L);
        return Math.max(1, leftSec);
    }

    private static boolean isTimeoutError(SQLException e) {
        String m = e.getMessage();
        if (m == null) {
            return false;
        }
        String lower = m.toLowerCase(java.util.Locale.ROOT);
        return lower.contains("timeout") || lower.contains("timed out") || lower.contains("cancel");
    }

    enum Kind { PROMPT, PLSQL, SQL, SKIP }

    static class Segment {
        final Kind kind;
        final String text;

        Segment(Kind kind, String text) {
            this.kind = kind;
            this.text = text;
        }
    }

    static List<Segment> parse(String script) {
        List<Segment> out = new ArrayList<Segment>();
        String[] lines = script.split("\n", -1);
        int i = 0;
        while (i < lines.length) {
            String raw = lines[i];
            String s = raw.trim();
            String su = s.toUpperCase(java.util.Locale.ROOT);
            if (s.isEmpty() || s.startsWith("--")) {
                i++;
                continue;
            }
            if (su.startsWith("SET ") || su.startsWith("COL ") || su.startsWith("COLUMN ")
                    || su.startsWith("DEFINE ") || su.startsWith("UNDEFINE ")
                    || su.startsWith("WHENEVER ")) {
                out.add(new Segment(Kind.SKIP, s));
                i++;
                continue;
            }
            if (su.startsWith("PROMPT") || su.equals("PRO") || su.startsWith("PRO ")) {
                String text;
                if (su.equals("PROMPT") || su.equals("PRO")) {
                    text = "";
                } else if (su.startsWith("PROMPT") && s.length() > 6 && Character.isWhitespace(s.charAt(6))) {
                    text = s.substring(7);
                } else if (su.startsWith("PRO ") ) {
                    text = s.substring(4);
                } else {
                    text = s.substring(6).trim();
                }
                out.add(new Segment(Kind.PROMPT, text));
                i++;
                continue;
            }
            if (su.startsWith("DECLARE") || su.startsWith("BEGIN")) {
                StringBuilder body = new StringBuilder();
                while (i < lines.length) {
                    String ln = lines[i];
                    if (ln.trim().equals("/")) {
                        i++;
                        break;
                    }
                    body.append(ln).append('\n');
                    i++;
                }
                out.add(new Segment(Kind.PLSQL, body.toString().trim()));
                continue;
            }
            if (su.startsWith("SELECT") || su.startsWith("WITH")) {
                StringBuilder body = new StringBuilder();
                while (i < lines.length) {
                    String ln = lines[i];
                    String t = ln.trim();
                    if (t.equals("/")) {
                        i++;
                        break;
                    }
                    body.append(ln).append('\n');
                    if (t.endsWith(";") && !t.startsWith("--")) {
                        i++;
                        break;
                    }
                    i++;
                }
                String sql = body.toString().trim();
                if (sql.endsWith(";")) {
                    sql = sql.substring(0, sql.length() - 1).trim();
                }
                out.add(new Segment(Kind.SQL, sql));
                continue;
            }
            // 未知行跳过
            if (loggableUnknown(s)) {
                out.add(new Segment(Kind.SKIP, s));
            }
            i++;
        }
        return out;
    }

    private static boolean loggableUnknown(String s) {
        return false;
    }

    /**
     * 追加 PLAN 起的 PROMPT+SELECT ({@link ReportSelectScript}).
     * AWR 失败写 [ERROR] AWR 并继续; 跳过 PLSQL.
     */
    public void appendFromPlan(JdbcSession session, String sqlId, StringBuilder out,
            long deadlineMs, int timeoutSec) throws SQLException, IOException {
        String template = loadTemplate();
        if (template == null || template.isEmpty()) {
            out.append("[ERROR] ReportSelectScript missing; SELECT sections skipped\n");
            if (log != null) {
                log.logWarn("SELECT sections skipped: ReportSelectScript empty");
            }
            return;
        }
        String script = substituteSqlId(template, sqlId);
        List<Segment> segs = parse(script);
        int start = -1;
        for (int i = 0; i < segs.size(); i++) {
            Segment seg = segs.get(i);
            if (seg.kind == Kind.PROMPT && seg.text != null
                    && seg.text.toUpperCase(java.util.Locale.ROOT).contains("PLAN FROM V$SQL_PLAN")) {
                start = i;
                break;
            }
        }
        if (start < 0) {
            out.append("[ERROR] PLAN section marker not found in ReportSelectScript\n");
            return;
        }
        Connection c = session.getConnection();
        boolean nextSqlIsAwr = false;
        for (int i = start; i < segs.size(); i++) {
            if (System.currentTimeMillis() > deadlineMs) {
                out.append("[ERROR] report timeout after ").append(timeoutSec).append("s\n");
                if (log != null) {
                    log.logWarn("report timeout during SELECT sections sql_id=" + sqlId);
                }
                return;
            }
            Segment seg = segs.get(i);
            int stmtTimeout = remainingQueryTimeoutSec(deadlineMs, timeoutSec);
            switch (seg.kind) {
                case PROMPT:
                    if (isAwrPrompt(seg.text)) {
                        nextSqlIsAwr = true;
                    }
                    out.append(seg.text).append('\n');
                    break;
                case SQL:
                    try {
                        executeQuery(c, seg.text, out, stmtTimeout);
                    } catch (SQLException e) {
                        if (nextSqlIsAwr) {
                            // P2: AWR 失败不中断 OBJECT SIZE 等后续段
                            out.append("[ERROR] AWR: ").append(e.getMessage()).append('\n');
                            if (log != null) {
                                log.logDbg("report AWR failed sql_id=" + sqlId + ": " + e.getMessage());
                            }
                            nextSqlIsAwr = false;
                            break;
                        }
                        if (isTimeoutError(e)) {
                            out.append("[ERROR] report timeout after ").append(timeoutSec).append("s\n");
                            if (log != null) {
                                log.logWarn("report timeout sql_id=" + sqlId + ": " + e.getMessage());
                            }
                            return;
                        }
                        out.append("[ERROR] SQL: ").append(e.getMessage()).append('\n');
                        if (log != null) {
                            log.logDbg("report SQL failed: " + e.getMessage());
                        }
                    }
                    nextSqlIsAwr = false;
                    break;
                case PLSQL:
                case SKIP:
                default:
                    break;
            }
        }
    }

    private static boolean isAwrPrompt(String text) {
        if (text == null) {
            return false;
        }
        String u = text.toUpperCase(java.util.Locale.ROOT);
        return u.contains("AWR") || u.contains("WRH$_SQLSTAT");
    }

    static void executeQuery(Connection c, String sql, StringBuilder out, int queryTimeoutSec)
            throws SQLException {
        try (Statement st = c.createStatement()) {
            if (queryTimeoutSec > 0) {
                st.setQueryTimeout(queryTimeoutSec);
            }
            try (ResultSet rs = st.executeQuery(sql)) {
                ResultSetMetaData md = rs.getMetaData();
                int cols = md.getColumnCount();
                if (cols == 1) {
                    while (rs.next()) {
                        String v = rs.getString(1);
                        out.append(v == null ? "" : v).append('\n');
                    }
                    return;
                }
                int[] widths = new int[cols];
                String[] headers = new String[cols];
                for (int i = 1; i <= cols; i++) {
                    headers[i - 1] = md.getColumnLabel(i);
                    widths[i - 1] = Math.max(headers[i - 1].length(), 1);
                }
                List<String[]> rows = new ArrayList<String[]>();
                while (rs.next()) {
                    String[] row = new String[cols];
                    for (int i = 1; i <= cols; i++) {
                        String v = rs.getString(i);
                        if (v == null) {
                            v = "";
                        }
                        v = v.replace('\n', ' ').replace('\r', ' ');
                        row[i - 1] = v;
                        if (v.length() > widths[i - 1]) {
                            widths[i - 1] = Math.min(v.length(), 80);
                        }
                    }
                    rows.add(row);
                }
                for (int i = 0; i < cols; i++) {
                    out.append(pad(headers[i], widths[i]));
                    if (i < cols - 1) {
                        out.append(' ');
                    }
                }
                out.append('\n');
                for (int i = 0; i < cols; i++) {
                    out.append(repeat('-', widths[i]));
                    if (i < cols - 1) {
                        out.append(' ');
                    }
                }
                out.append('\n');
                for (String[] row : rows) {
                    for (int i = 0; i < cols; i++) {
                        String v = row[i];
                        if (v.length() > widths[i]) {
                            v = v.substring(0, widths[i]);
                        }
                        out.append(pad(v, widths[i]));
                        if (i < cols - 1) {
                            out.append(' ');
                        }
                    }
                    out.append('\n');
                }
            }
        }
    }

    private static String pad(String s, int w) {
        if (s.length() >= w) {
            return s;
        }
        StringBuilder sb = new StringBuilder(s);
        while (sb.length() < w) {
            sb.append(' ');
        }
        return sb.toString();
    }

    private static String repeat(char c, int n) {
        StringBuilder sb = new StringBuilder(n);
        for (int i = 0; i < n; i++) {
            sb.append(c);
        }
        return sb.toString();
    }
}
