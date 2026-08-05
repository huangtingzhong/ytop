package com.yashan.sqlcollect.sqlmap;

import com.yashan.sqlcollect.config.JdbcConfig;
import com.yashan.sqlcollect.db.JdbcPool;
import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.db.SqlLookup;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.replay.SqlExecutor;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.util.List;

/** genexec / perf */
public final class SqlMapExec {

    private SqlMapExec() {
    }

    public static int genexec(JdbcConfig cfg, JdbcPool pool, SqlMapArgs a, DualLogger log) {
        try {
            JdbcSession sess = new JdbcSession(cfg, log, pool);
            try {
                Connection c = sess.getConnection();
                String sql;
                String schema = cfg.currentSchema;
                String tgtId = a.opt("tgt-sql-id", null);
                if (tgtId != null && !tgtId.trim().isEmpty()) {
                    SqlLookup.SqlTextInfo info = SqlLookup.loadSqlText(c, tgtId.trim(),
                            SqlMapIo.warn(log));
                    if (!info.found) {
                        log.logError("target sql_id not found: " + tgtId);
                        return 1;
                    }
                    sql = info.sqlText;
                    if (schema == null || schema.isEmpty()) {
                        schema = info.schema;
                    }
                } else {
                    sql = SqlMapIo.readFile(a.opt("sql-file", ""));
                }
                String marker = a.opt("marker", null);
                if (marker != null && !marker.isEmpty()) {
                    sql = sql + "\n/* " + marker + " */";
                }
                List<String[]> binds = resolveBinds(c, a, log);
                int ph = SqlExecutor.countPlaceholders(sql);
                log.logInfo("genexec placeholders=" + ph + " binds=" + binds.size()
                        + " kind=" + SqlExecutor.classifySql(sql)
                        + " exec=" + a.resolveExec());
                if (ph > 0 && binds.size() < ph) {
                    log.logError("bind count " + binds.size() + " < placeholders " + ph
                            + "; provide -b or -s for genbind");
                    return 1;
                }
                boolean dry = !a.resolveExec();
                SqlExecutor.LineOut out = new SqlExecutor.LineOut() {
                    public void println(String line) {
                        log.logInfo(line);
                    }
                };
                SqlExecutor.ExecResult r = SqlExecutor.execute(
                        dry ? null : c, schema, sql, binds, dry, true,
                        cfg.user, 0, false, 20, out);
                String outPath = a.opt("out", null);
                if (outPath != null && !outPath.isEmpty()) {
                    StringBuilder sb = new StringBuilder();
                    sb.append("-- genexec summary dry=").append(dry).append('\n');
                    sb.append("-- kind=").append(r.kind).append(" ok=").append(r.ok)
                            .append(" elapsed_ms=").append(r.elapsedMs).append('\n');
                    sb.append(sql);
                    Files.write(Paths.get(outPath), sb.toString().getBytes(StandardCharsets.UTF_8));
                }
                if (!r.ok) {
                    log.logError("genexec failed: " + r.error);
                    return 1;
                }
                System.out.println("[OK] genexec " + (dry ? "dry-run" : "exec")
                        + " elapsed_ms=" + r.elapsedMs);
                return 0;
            } finally {
                sess.close();
            }
        } catch (Exception e) {
            log.logError("genexec failed: " + e.getMessage());
            return 1;
        }
    }

    public static int perf(JdbcConfig cfg, JdbcPool pool, SqlMapArgs a, DualLogger log) {
        try {
            JdbcSession sess = new JdbcSession(cfg, log, pool);
            try {
                Connection c = sess.getConnection();
                String srcId = a.opt("src-sql-id", "").trim();
                SqlLookup.SqlTextInfo srcInfo = SqlLookup.loadSqlText(c, srcId, SqlMapIo.warn(log));
                if (!srcInfo.found) {
                    log.logError("source sql_id not found: " + srcId);
                    return 1;
                }
                SqlMapDdl.Resolved tgt = SqlMapDdl.resolveSide(c, a, false, log);
                if (tgt.error != null) {
                    log.logError(tgt.error);
                    return 1;
                }
                List<String[]> binds = resolveBinds(c, a, log);
                if (binds.isEmpty()) {
                    binds = SqlLookup.toReplayRows(
                            SqlLookup.loadBindsBySqlId(c, srcId, SqlMapIo.warn(log)));
                }
                boolean dry = !a.resolveExec();
                SqlExecutor.LineOut out = new SqlExecutor.LineOut() {
                    public void println(String line) {
                        log.logInfo(line);
                    }
                };
                String schema = cfg.currentSchema;
                if (schema == null || schema.isEmpty()) {
                    schema = srcInfo.schema;
                }
                SqlExecutor.ExecResult srcR = SqlExecutor.execute(
                        dry ? null : c, schema, srcInfo.sqlText, binds, dry, true,
                        cfg.user, 0, false, 5, out);
                String marker = a.opt("marker", null);
                String tgtSql = tgt.text;
                if (marker != null && !marker.isEmpty() && !tgtSql.contains("/*")) {
                    tgtSql = tgtSql + "\n/* " + marker + " */";
                }
                SqlExecutor.ExecResult tgtR = SqlExecutor.execute(
                        dry ? null : c, schema, tgtSql, binds, dry, true,
                        cfg.user, 0, false, 5, out);

                SqlMapVerify.SqlStats srcSt = SqlMapVerify.lookupSqlStats(
                        c, srcId, srcInfo.sqlText, null, log);
                SqlMapVerify.SqlStats tgtSt = SqlMapVerify.lookupSqlStats(
                        c, tgt.sqlId, tgtSql, marker, log);

                StringBuilder summary = new StringBuilder();
                summary.append("perf dry=").append(dry).append('\n');
                summary.append(String.format(java.util.Locale.ROOT,
                        "src elapsed_ms=%d plan_hash=%s buffer_gets=%s executions=%s sql_id=%s%n",
                        Long.valueOf(srcR.elapsedMs),
                        srcSt == null ? "-" : String.valueOf(srcSt.planHash),
                        srcSt == null || srcSt.bufferGets == null ? "-" : String.valueOf(srcSt.bufferGets),
                        srcSt == null || srcSt.executions == null ? "-" : String.valueOf(srcSt.executions),
                        srcId));
                summary.append(String.format(java.util.Locale.ROOT,
                        "tgt elapsed_ms=%d plan_hash=%s buffer_gets=%s executions=%s sql_id=%s%n",
                        Long.valueOf(tgtR.elapsedMs),
                        tgtSt == null ? "-" : String.valueOf(tgtSt.planHash),
                        tgtSt == null || tgtSt.bufferGets == null ? "-" : String.valueOf(tgtSt.bufferGets),
                        tgtSt == null || tgtSt.executions == null ? "-" : String.valueOf(tgtSt.executions),
                        tgt.sqlId == null || tgt.sqlId.isEmpty()
                                ? (tgtSt == null ? "-" : tgtSt.sqlId) : tgt.sqlId));
                System.out.print(summary.toString());
                log.logInfo(summary.toString().trim().replace('\n', ' '));

                String outPath = a.opt("out", null);
                if (outPath != null && !outPath.isEmpty()) {
                    Files.write(Paths.get(outPath), summary.toString().getBytes(StandardCharsets.UTF_8));
                }
                if (!srcR.ok || !tgtR.ok) {
                    return 1;
                }
                System.out.println("[OK] perf done");
                return 0;
            } finally {
                sess.close();
            }
        } catch (Exception e) {
            log.logError("perf failed: " + e.getMessage());
            return 1;
        }
    }

    static List<String[]> resolveBinds(Connection c, SqlMapArgs a, DualLogger log) throws Exception {
        String bf = a.opt("bind-file", null);
        if (bf != null && !bf.isEmpty()) {
            return SqlMapIo.readValueLines(bf);
        }
        String srcId = a.opt("src-sql-id", null);
        if (srcId != null && !srcId.trim().isEmpty()) {
            return SqlLookup.toReplayRows(
                    SqlLookup.loadBindsBySqlId(c, srcId.trim(), SqlMapIo.warn(log)));
        }
        return new java.util.ArrayList<String[]>();
    }
}
