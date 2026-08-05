package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.cli.Args;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.util.RunDirResolver;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/**
 * 扫描 collect reports/&lt;sql_id&gt;.txt, 按性能列排序展示 Top SQL.
 * 默认按 db_time (= exec * ela_pe) 降序. 纯离线, 不需 JDBC.
 */
public class TopCommand {

    public static final String DEFAULT_LOG_DIR = "logs";
    public static final String REPORT_DIR = CollectCommand.REPORT_DIR;

    public int run(Args args) {
        DualLogger log = null;
        try {
            Path logDir = Paths.get(args.opt("log-dir", DEFAULT_LOG_DIR));
            log = new DualLogger(logDir, "top", args.resolveDebug());
            log.logInfo("top debug=" + args.resolveDebug());

            Path outArg = Paths.get(args.opt("outdir", CollectCommand.DEFAULT_OUTDIR));
            String runName = args.opt("run", null);
            Path reports;
            try {
                reports = resolveReportsDir(outArg, runName);
            } catch (IOException e) {
                log.logError(e.getMessage());
                return 2;
            }
            if (!Files.isDirectory(reports)) {
                log.logError("reports dir not found: " + reports);
                return 2;
            }

            int limit = args.optInt("limit", Integer.valueOf(50)).intValue();
            if (limit <= 0) {
                limit = Integer.MAX_VALUE;
            }
            SortSpec sort = SortSpec.parse(args.opt("sort", "db_time"));
            String csvPath = args.opt("csv", null);

            List<ReportSqlareaParser.Row> rows = new ArrayList<ReportSqlareaParser.Row>();
            int files = 0;
            int parseFail = 0;
            try (DirectoryStream<Path> ds = Files.newDirectoryStream(reports, "*.txt")) {
                for (Path f : ds) {
                    files++;
                    try {
                        ReportSqlareaParser.Row r = ReportSqlareaParser.parseFile(f);
                        if (!r.ok) {
                            parseFail++;
                        }
                        rows.add(r);
                    } catch (IOException e) {
                        parseFail++;
                        log.logDbg("parse fail " + f.getFileName() + ": " + e.getMessage());
                    }
                }
            }

            Collections.sort(rows, sort.comparator());
            int show = Math.min(limit, rows.size());

            Path runDir = reports.getFileName() != null
                    && REPORT_DIR.equals(reports.getFileName().toString())
                    && reports.getParent() != null
                    ? reports.getParent()
                    : reports;
            boolean legacyFlat = reports.getFileName() == null
                    || !REPORT_DIR.equals(reports.getFileName().toString());
            log.logInfo("run_dir=" + runDir + " reports_dir=" + reports
                    + " layout=" + (legacyFlat ? "legacy-flat" : "reports/")
                    + " reports=" + files
                    + " parse_fail=" + parseFail + " sort=" + sort.label
                    + " asc=" + sort.asc + " show=" + show);

            printTable(rows, show);
            System.out.println();
            System.out.println("[OK] top files=" + files + " parse_fail=" + parseFail
                    + " shown=" + show + " sort=" + sort.label
                    + (sort.asc ? ":asc" : ":desc"));

            if (csvPath != null && !csvPath.isEmpty()) {
                writeCsv(Paths.get(csvPath), rows, show);
                System.out.println("[OK] csv " + csvPath);
            }
            return 0;
        } catch (IOException e) {
            if (log != null) {
                log.logError(e.getMessage());
            } else {
                System.err.println("[ERROR] " + e.getMessage());
            }
            return 1;
        } finally {
            if (log != null) {
                log.close();
            }
        }
    }

    /**
     * 解析报告所在目录 (含 *.txt).
     * 支持: outdir/reports、run/reports、outdir 根下直接 *.txt (旧布局).
     */
    static Path resolveReportsDir(Path outdirArg, String runName) throws IOException {
        Path out = outdirArg.toAbsolutePath().normalize();
        if (runName != null && !runName.trim().isEmpty()) {
            Path run = out.resolve(runName.trim());
            Path std = run.resolve(REPORT_DIR);
            if (Files.isDirectory(std)) {
                return std;
            }
            if (isLegacyFlatReportsDir(run)) {
                return run;
            }
            throw new IOException("run reports not found: " + std
                    + " (also checked legacy flat *.txt under " + run + ")");
        }
        // -o 已直接指向 reports/ 子目录
        if (out.getFileName() != null && REPORT_DIR.equals(out.getFileName().toString())
                && Files.isDirectory(out)) {
            return out;
        }
        String name = out.getFileName() == null ? "" : out.getFileName().toString();
        if (RunDirResolver.RUN_DIR_NAME.matcher(name).matches()) {
            Path std = out.resolve(REPORT_DIR);
            if (Files.isDirectory(std)) {
                return std;
            }
            if (isLegacyFlatReportsDir(out)) {
                return out;
            }
        }
        Path stdOut = out.resolve(REPORT_DIR);
        if (Files.isDirectory(stdOut)) {
            return stdOut; // 标准: 基目录/reports 或 无时间戳的扁平
        }
        if (isLegacyFlatReportsDir(out)) {
            return out; // 旧布局: 报告 txt 直接在 -o 目录下
        }
        Path latest = RunDirResolver.findLatestRunDir(out);
        if (latest != null) {
            Path std = latest.resolve(REPORT_DIR);
            if (Files.isDirectory(std)) {
                return std;
            }
            if (isLegacyFlatReportsDir(latest)) {
                return latest;
            }
        }
        throw new IOException("no reports under " + out
                + " (need reports/*.txt, or legacy flat *.txt, or --run <yyyyMMddHHmmss>)");
    }

    /** 旧布局: 目录下没有 reports/ 子目录, 但有至少一份 *.txt 报告. */
    static boolean isLegacyFlatReportsDir(Path dir) throws IOException {
        if (!Files.isDirectory(dir)) {
            return false;
        }
        if (Files.isDirectory(dir.resolve(REPORT_DIR))) {
            return false;
        }
        try (DirectoryStream<Path> ds = Files.newDirectoryStream(dir, "*.txt")) {
            return ds.iterator().hasNext();
        }
    }

    /** @deprecated 使用 {@link #resolveReportsDir}. */
    static Path resolveReportsRunDir(Path outdirArg, String runName) throws IOException {
        Path reports = resolveReportsDir(outdirArg, runName);
        if (reports.getFileName() != null && REPORT_DIR.equals(reports.getFileName().toString())
                && reports.getParent() != null) {
            return reports.getParent();
        }
        return reports;
    }

    private static void printTable(List<ReportSqlareaParser.Row> rows, int show) {
        // 列: 文本左齐, 数值右齐; 宽度按本批数据动态取 max(表头, 单元格)
        final String[] headers = {
            "RANK", "SQL_ID", "SCHEMA", "EXEC", "DB_TIME", "CPU", "ELA_P_E", "GET_P_E", "PHV", "SRC"
        };
        // true=右对齐 (数值/时间/PHV)
        final boolean[] right = {
            true, false, false, true, true, true, true, true, true, false
        };
        List<String[]> cells = new ArrayList<String[]>(show);
        for (int i = 0; i < show; i++) {
            ReportSqlareaParser.Row r = rows.get(i);
            String getPe = !r.ok || Double.isNaN(r.getPe) ? "-"
                    : String.format(Locale.ROOT, "%.2f", Double.valueOf(r.getPe));
            cells.add(new String[] {
                Integer.toString(i + 1),
                nullToEmpty(r.sqlId),
                nullToEmpty(r.schema),
                Long.toString(r.exec),
                r.ok ? r.displayDbTime() : "-",
                r.ok ? r.displayCpu() : "-",
                r.ok ? emptyDash(r.displayElaPe()) : "-",
                getPe,
                nullToEmpty(r.phv).isEmpty() ? "-" : r.phv,
                nullToEmpty(r.source).isEmpty() ? "-" : r.source
            });
        }
        int cols = headers.length;
        int[] width = new int[cols];
        for (int c = 0; c < cols; c++) {
            width[c] = headers[c].length();
        }
        for (int i = 0; i < cells.size(); i++) {
            String[] row = cells.get(i);
            for (int c = 0; c < cols; c++) {
                if (row[c].length() > width[c]) {
                    width[c] = row[c].length();
                }
            }
        }
        printAlignedRow(headers, width, right);
        printSeparator(width);
        for (int i = 0; i < cells.size(); i++) {
            printAlignedRow(cells.get(i), width, right);
        }
    }

    private static String emptyDash(String s) {
        return s == null || s.isEmpty() ? "-" : s;
    }

    private static void printAlignedRow(String[] cells, int[] width, boolean[] right) {
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < cells.length; c++) {
            if (c > 0) {
                sb.append(' ');
            }
            String v = cells[c] == null ? "" : cells[c];
            int pad = width[c] - v.length();
            if (pad < 0) {
                pad = 0;
            }
            if (right[c]) {
                for (int i = 0; i < pad; i++) {
                    sb.append(' ');
                }
                sb.append(v);
            } else {
                sb.append(v);
                for (int i = 0; i < pad; i++) {
                    sb.append(' ');
                }
            }
        }
        System.out.println(sb.toString());
    }

    private static void printSeparator(int[] width) {
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < width.length; c++) {
            if (c > 0) {
                sb.append(' ');
            }
            for (int i = 0; i < width[c]; i++) {
                sb.append('-');
            }
        }
        System.out.println(sb.toString());
    }

    private static void writeCsv(Path path, List<ReportSqlareaParser.Row> rows, int show)
            throws IOException {
        Path parent = path.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        try (BufferedWriter w = Files.newBufferedWriter(path, StandardCharsets.UTF_8)) {
            w.write("rank,sql_id,schema,exec,db_time_us,cpu_time_us,ela_pe_us,cpu_pe_us,"
                    + "get_pe,gets_total,phv,source,ok,error\n");
            for (int i = 0; i < show; i++) {
                ReportSqlareaParser.Row r = rows.get(i);
                w.write(Integer.toString(i + 1));
                w.write(',');
                w.write(csv(r.sqlId));
                w.write(',');
                w.write(csv(r.schema));
                w.write(',');
                w.write(Long.toString(r.exec));
                w.write(',');
                w.write(Long.toString(r.dbTimeUs));
                w.write(',');
                w.write(Long.toString(r.cpuTimeUs));
                w.write(',');
                w.write(Long.toString(r.elaPeUs));
                w.write(',');
                w.write(Long.toString(r.cpuPeUs));
                w.write(',');
                w.write(Double.isNaN(r.getPe) ? "" : Double.toString(r.getPe));
                w.write(',');
                w.write(Double.isNaN(r.getsTotal) ? "" : Double.toString(r.getsTotal));
                w.write(',');
                w.write(csv(r.phv));
                w.write(',');
                w.write(csv(r.source));
                w.write(',');
                w.write(r.ok ? "1" : "0");
                w.write(',');
                w.write(csv(r.error));
                w.write('\n');
            }
        }
    }

    private static String csv(String s) {
        if (s == null) {
            return "";
        }
        if (s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\n') >= 0) {
            return '"' + s.replace("\"", "\"\"") + '"';
        }
        return s;
    }

    private static String nullToEmpty(String s) {
        return s == null ? "" : s;
    }

    static final class SortSpec {
        final String label;
        final boolean asc;

        SortSpec(String label, boolean asc) {
            this.label = label;
            this.asc = asc;
        }

        static SortSpec parse(String raw) {
            String s = raw == null ? "db_time" : raw.trim().toLowerCase(Locale.ROOT);
            boolean asc = false;
            if (s.endsWith(":asc")) {
                asc = true;
                s = s.substring(0, s.length() - 4);
            } else if (s.endsWith(":desc")) {
                asc = false;
                s = s.substring(0, s.length() - 5);
            }
            if ("elapsed".equals(s) || "ela".equals(s)) {
                s = "db_time";
            } else if ("buffer_gets".equals(s) || "gets_total".equals(s)) {
                s = "gets";
            } else if ("executions".equals(s)) {
                s = "exec";
            } else if ("cpu_time".equals(s)) {
                s = "cpu";
            }
            return new SortSpec(s, asc);
        }

        Comparator<ReportSqlareaParser.Row> comparator() {
            final Comparator<ReportSqlareaParser.Row> key;
            if ("cpu".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return Long.compare(a.cpuTimeUs, b.cpuTimeUs);
                    }
                };
            } else if ("ela_pe".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return Long.compare(a.elaPeUs, b.elaPeUs);
                    }
                };
            } else if ("cpu_pe".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return Long.compare(a.cpuPeUs, b.cpuPeUs);
                    }
                };
            } else if ("exec".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return Long.compare(a.exec, b.exec);
                    }
                };
            } else if ("gets".equals(label) || "get_pe".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        double ga = "get_pe".equals(label) ? a.getPe : a.getsTotal;
                        double gb = "get_pe".equals(label) ? b.getPe : b.getsTotal;
                        if (Double.isNaN(ga) && Double.isNaN(gb)) {
                            return 0;
                        }
                        if (Double.isNaN(ga)) {
                            return -1;
                        }
                        if (Double.isNaN(gb)) {
                            return 1;
                        }
                        return Double.compare(ga, gb);
                    }
                };
            } else if ("sql_id".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return a.sqlId.compareTo(b.sqlId);
                    }
                };
            } else if ("schema".equals(label)) {
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return a.schema.compareTo(b.schema);
                    }
                };
            } else { // db_time default
                key = new Comparator<ReportSqlareaParser.Row>() {
                    public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                        return Long.compare(a.dbTimeUs, b.dbTimeUs);
                    }
                };
            }
            // 无统计的排最后
            Comparator<ReportSqlareaParser.Row> withOk = new Comparator<ReportSqlareaParser.Row>() {
                public int compare(ReportSqlareaParser.Row a, ReportSqlareaParser.Row b) {
                    if (a.ok != b.ok) {
                        return a.ok ? -1 : 1;
                    }
                    int c = key.compare(a, b);
                    return asc ? c : -c;
                }
            };
            return withOk;
        }
    }

    public static void printHelp() {
        System.out.println("sql-collect top - Rank SQL from collect reports/*.txt");
        System.out.println();
        System.out.println("Usage:");
        System.out.println("  sql-collect top [options]");
        System.out.println();
        System.out.println("Options:");
        Args.helpOpt("-o, --outdir <dir>", "Collect base or run dir (default: ./sql_collect)");
        Args.helpOpt("--run <yyyyMMddHHmmss>", "Run subdirectory under -o (optional)");
        Args.helpOpt("-L, --limit <n>", "Show top N rows (default: 50; 0=all)");
        Args.helpOpt("--sort <col[:asc|desc]>", "Sort key (default: db_time:desc)");
        Args.helpOpt("", "cols: db_time|cpu|ela_pe|cpu_pe|exec|gets|get_pe|sql_id|schema");
        Args.helpOpt("--csv <file>", "Also write CSV for shown rows");
        Args.helpOpt("-l, --log-dir <dir>", "Log directory (default: ./logs)");
        Args.helpOpt("-d, --debug [bool]", "Debug logging (default: on)");
        Args.helpOpt("-h, --help", "Show this help");
        System.out.println();
        System.out.println("Notes:");
        System.out.println("  - Scans reports/*.txt; also accepts legacy flat dir with *.txt at -o root.");
        System.out.println("  - Does not scan skipped/ or replay/.");
        System.out.println("  - db_time = exec * ela_pe (from v$sqlarea; fallback v$sql sum).");
        System.out.println("  - Offline; JDBC not required.");
        System.out.println();
        System.out.println("Examples:");
        System.out.println("  sql-collect top -o ./sql_collect");
        System.out.println("  sql-collect top -o ./sql_collect -L 20 --sort cpu");
        System.out.println("  sql-collect top -o ./sql_collect --run 20260805004136 --csv top.csv");
        System.out.println("  sql-collect top -o ./legacy_flat_reports_dir  # *.txt directly under -o");
        System.out.println("  sql-collect top -o ./sql_collect/20260805004136 --sort exec:asc");
    }
}
