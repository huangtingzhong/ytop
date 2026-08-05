package com.yashan.sqlcollect.collect;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 从 reports/&lt;sql_id&gt;.txt 解析 v$sqlarea (或回退 v$sql) 性能行.
 * 展示串换算为内部数值, 供 top 排序.
 */
public final class ReportSqlareaParser {

    private static final Pattern SCHEMA = Pattern.compile(
            "Schema:\\s*(\\S+)", Pattern.CASE_INSENSITIVE);
    // 允许 .01ms 这种前导小数点
    private static final Pattern TIME = Pattern.compile(
            "^([0-9]*\\.?[0-9]+)(ms|s|m|h)$", Pattern.CASE_INSENSITIVE);
    private static final Pattern COUNT = Pattern.compile(
            "^([0-9]*\\.?[0-9]+)([KkWw])?$");

    private ReportSqlareaParser() {
    }

    /** 单条 SQL 报告解析结果 */
    public static final class Row {
        public String sqlId = "";
        public String schema = "";
        public String phv = "";
        public String source = ""; // sqlarea | sql | none
        public long exec;
        public long cpuPeUs = -1;
        public long elaPeUs = -1;
        public double getPe = Double.NaN;
        public double rowsPe = Double.NaN;
        public long dbTimeUs;
        public long cpuTimeUs;
        public double getsTotal = Double.NaN;
        public boolean ok;
        public String error = "";

        public String displayDbTime() {
            return formatUs(dbTimeUs);
        }

        public String displayCpu() {
            return formatUs(cpuTimeUs);
        }

        public String displayElaPe() {
            return elaPeUs < 0 ? "" : formatUs(elaPeUs);
        }

        public String displayCpuPe() {
            return cpuPeUs < 0 ? "" : formatUs(cpuPeUs);
        }
    }

    public static Row parseFile(Path file) throws IOException {
        Row row = new Row();
        String name = file.getFileName().toString();
        if (name.toLowerCase(Locale.ROOT).endsWith(".txt")) {
            row.sqlId = name.substring(0, name.length() - 4);
        } else {
            row.sqlId = name;
        }

        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
            String line;
            while ((line = br.readLine()) != null) {
                sb.append(line).append('\n');
                if (row.schema.isEmpty()) {
                    Matcher m = SCHEMA.matcher(line);
                    if (m.find()) {
                        row.schema = m.group(1);
                    }
                }
            }
        }
        String text = sb.toString();

        if (fillFromSection(row, text, "information from v$sqlarea", true)) {
            row.source = "sqlarea";
            row.ok = true;
            finalizeTotals(row);
            return row;
        }
        if (fillFromSection(row, text, "information from v$sql", false)) {
            row.source = "sql";
            row.ok = true;
            finalizeTotals(row);
            return row;
        }
        row.source = "none";
        row.ok = false;
        row.error = "no sqlarea/sql stats rows";
        return row;
    }

    private static void finalizeTotals(Row row) {
        // fillFromSection 多行时已累加 total; 仅在缺失时用 pe*exec 补齐
        if (row.dbTimeUs <= 0 && row.elaPeUs >= 0) {
            row.dbTimeUs = mulNonNeg(row.exec, row.elaPeUs);
        }
        if (row.cpuTimeUs <= 0 && row.cpuPeUs >= 0) {
            row.cpuTimeUs = mulNonNeg(row.exec, row.cpuPeUs);
        }
        if (Double.isNaN(row.getsTotal) && !Double.isNaN(row.getPe)) {
            row.getsTotal = row.exec * row.getPe;
        }
    }

    private static long mulNonNeg(long a, long b) {
        if (a <= 0 || b <= 0) {
            return 0;
        }
        if (a > 0 && b > Long.MAX_VALUE / a) {
            return Long.MAX_VALUE;
        }
        return a * b;
    }

    /**
     * @param sqlarea true=PHV 在首列; false=v$sql 行 EXEC 在首列
     */
    private static boolean fillFromSection(Row row, String text, String marker, boolean sqlarea) {
        int idx = indexOfIgnoreCase(text, marker);
        if (idx < 0) {
            return false;
        }
        String rest = text.substring(idx);
        String[] lines = rest.split("\n");
        boolean seenHeader = false;
        boolean seenDash = false;
        long sumDb = 0;
        long sumCpu = 0;
        long sumExec = 0;
        double sumGets = 0;
        boolean anyGets = false;
        long bestElaPe = -1;
        long bestCpuPe = -1;
        double bestGetPe = Double.NaN;
        double bestRowsPe = Double.NaN;
        String bestPhv = "";
        int dataRows = 0;

        for (int i = 0; i < lines.length; i++) {
            String line = lines[i];
            String trim = line.trim();
            // 段前装饰线 (+--- / | information...) 在见到表头前忽略
            if (!seenHeader) {
                if (sqlarea && trim.startsWith("PHV") && trim.contains("ELA_P_E")) {
                    seenHeader = true;
                } else if (!sqlarea && trim.startsWith("EXEC") && trim.contains("ELA_P_E")) {
                    seenHeader = true;
                }
                continue;
            }
            if (!seenDash) {
                if (trim.startsWith("----")) {
                    seenDash = true;
                }
                continue;
            }
            // 表体结束: 下一框线 / 下一 information 段 / 空行(已有数据)
            if (trim.startsWith("+---") || trim.startsWith("| information from")
                    || trim.startsWith("*****")) {
                break;
            }
            if (trim.isEmpty()) {
                if (dataRows > 0) {
                    break;
                }
                continue;
            }
            String[] tok = trim.split("\\s+");
            ParsedLine pl = sqlarea ? parseSqlareaTokens(tok) : parseSqlTokens(tok);
            if (pl == null) {
                continue;
            }
            dataRows++;
            sumExec += pl.exec;
            if (pl.elaPeUs >= 0) {
                sumDb += mulNonNeg(pl.exec, pl.elaPeUs);
                if (bestElaPe < 0 || pl.elaPeUs > bestElaPe) {
                    bestElaPe = pl.elaPeUs;
                }
            }
            if (pl.cpuPeUs >= 0) {
                sumCpu += mulNonNeg(pl.exec, pl.cpuPeUs);
                if (bestCpuPe < 0 || pl.cpuPeUs > bestCpuPe) {
                    bestCpuPe = pl.cpuPeUs;
                }
            }
            if (!Double.isNaN(pl.getPe)) {
                sumGets += pl.exec * pl.getPe;
                anyGets = true;
                if (Double.isNaN(bestGetPe)) {
                    bestGetPe = pl.getPe;
                }
            }
            if (!Double.isNaN(pl.rowsPe) && Double.isNaN(bestRowsPe)) {
                bestRowsPe = pl.rowsPe;
            }
            if (bestPhv.isEmpty() && pl.phv != null) {
                bestPhv = pl.phv;
            }
        }

        if (dataRows == 0) {
            return false;
        }
        row.exec = sumExec;
        row.dbTimeUs = sumDb;
        row.cpuTimeUs = sumCpu;
        row.elaPeUs = bestElaPe;
        row.cpuPeUs = bestCpuPe;
        row.getPe = bestGetPe;
        row.rowsPe = bestRowsPe;
        row.phv = bestPhv;
        if (anyGets) {
            row.getsTotal = sumGets;
        }
        // 多行已直接累加 total; 单行 finalize 再用 pe*exec 亦可, 此处标记 pe 已用于 total
        return true;
    }

    private static final class ParsedLine {
        String phv;
        long exec;
        long cpuPeUs = -1;
        long elaPeUs = -1;
        double getPe = Double.NaN;
        double rowsPe = Double.NaN;
    }

    /** sqlarea: PHV EXEC CPU ELA DISK GET ROWS_PE ... */
    private static ParsedLine parseSqlareaTokens(String[] tok) {
        if (tok.length < 6) {
            return null;
        }
        if (!looksLikePhv(tok[0])) {
            return null;
        }
        Long exec = parseCount(tok[1]);
        if (exec == null) {
            return null;
        }
        ParsedLine p = new ParsedLine();
        p.phv = tok[0];
        p.exec = exec.longValue();
        p.cpuPeUs = parseTimeUs(tok[2]);
        p.elaPeUs = parseTimeUs(tok[3]);
        // tok[4]=DISK
        p.getPe = parseNumber(tok[5]);
        if (tok.length > 6) {
            p.rowsPe = parseNumber(tok[6]);
        }
        return p;
    }

    /** v$sql: EXEC PHV C USERNAME CPU ELA DISK GET ... */
    private static ParsedLine parseSqlTokens(String[] tok) {
        if (tok.length < 8) {
            return null;
        }
        Long exec = parseCount(tok[0]);
        if (exec == null || !looksLikePhv(tok[1])) {
            return null;
        }
        ParsedLine p = new ParsedLine();
        p.exec = exec.longValue();
        p.phv = tok[1];
        // tok[2]=child flag, tok[3]=username
        p.cpuPeUs = parseTimeUs(tok[4]);
        p.elaPeUs = parseTimeUs(tok[5]);
        p.getPe = parseNumber(tok[7]);
        if (tok.length > 8) {
            p.rowsPe = parseNumber(tok[8]);
        }
        return p;
    }

    private static boolean looksLikePhv(String s) {
        if (s == null || s.isEmpty()) {
            return false;
        }
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c < '0' || c > '9') {
                return false;
            }
        }
        return true;
    }

    /** @return 微秒; 无法解析返回 -1 */
    static long parseTimeUs(String raw) {
        if (raw == null) {
            return -1;
        }
        String s = raw.trim();
        if (s.isEmpty() || "NULL".equalsIgnoreCase(s) || "-".equals(s)) {
            return -1;
        }
        Matcher m = TIME.matcher(s);
        if (!m.matches()) {
            // 纯数字按 ms
            Double n = parseNumber(s);
            if (n == null || Double.isNaN(n.doubleValue())) {
                return -1;
            }
            return Math.round(n.doubleValue() * 1000.0);
        }
        double v = Double.parseDouble(m.group(1));
        String u = m.group(2).toLowerCase(Locale.ROOT);
        double us;
        if ("ms".equals(u)) {
            us = v * 1000.0;
        } else if ("s".equals(u)) {
            us = v * 1000.0 * 1000.0;
        } else if ("m".equals(u)) {
            us = v * 60.0 * 1000.0 * 1000.0;
        } else { // h
            us = v * 3600.0 * 1000.0 * 1000.0;
        }
        if (us > Long.MAX_VALUE) {
            return Long.MAX_VALUE;
        }
        return Math.round(us);
    }

    static Long parseCount(String raw) {
        if (raw == null) {
            return null;
        }
        String s = raw.trim();
        Matcher m = COUNT.matcher(s);
        if (!m.matches()) {
            return null;
        }
        double v = Double.parseDouble(m.group(1));
        String suf = m.group(2);
        if (suf != null) {
            char c = Character.toUpperCase(suf.charAt(0));
            if (c == 'K') {
                v *= 1000.0;
            } else if (c == 'W') {
                v *= 10000.0;
            }
        }
        if (v > Long.MAX_VALUE) {
            return Long.valueOf(Long.MAX_VALUE);
        }
        return Long.valueOf(Math.round(v));
    }

    static Double parseNumber(String raw) {
        if (raw == null) {
            return Double.valueOf(Double.NaN);
        }
        String s = raw.trim();
        if (s.isEmpty() || "NULL".equalsIgnoreCase(s) || "-".equals(s)) {
            return Double.valueOf(Double.NaN);
        }
        Matcher m = COUNT.matcher(s);
        if (!m.matches()) {
            return Double.valueOf(Double.NaN);
        }
        double v = Double.parseDouble(m.group(1));
        String suf = m.group(2);
        if (suf != null) {
            char c = Character.toUpperCase(suf.charAt(0));
            if (c == 'K') {
                v *= 1000.0;
            } else if (c == 'W') {
                v *= 10000.0;
            }
        }
        return Double.valueOf(v);
    }

    static String formatUs(long us) {
        if (us < 0) {
            return "";
        }
        if (us < 1000L) {
            return us + "us";
        }
        double ms = us / 1000.0;
        if (ms < 1000.0) {
            return trimNum(ms) + "ms";
        }
        double sec = ms / 1000.0;
        if (sec < 60.0) {
            return trimNum(sec) + "s";
        }
        double min = sec / 60.0;
        if (min < 60.0) {
            return trimNum(min) + "m";
        }
        return trimNum(min / 60.0) + "h";
    }

    private static String trimNum(double v) {
        if (Math.abs(v - Math.rint(v)) < 1e-9) {
            return Long.toString(Math.round(v));
        }
        return String.format(Locale.ROOT, "%.2f", Double.valueOf(v));
    }

    private static int indexOfIgnoreCase(String text, String needle) {
        return text.toLowerCase(Locale.ROOT).indexOf(needle.toLowerCase(Locale.ROOT));
    }
}
