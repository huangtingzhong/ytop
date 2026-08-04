package com.yashan.sqlcollect.replay;

import com.yashan.sqlcollect.db.HtzTables;
import com.yashan.sqlcollect.db.JdbcPool;
import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.model.ReplayPackageMeta;
import com.yashan.sqlcollect.util.JsonBinds;
import com.yashan.sqlcollect.util.PipeEscape;

import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** JDBC replay 引擎 (file/htz/gv), 进程内调用; 连接经 {@link JdbcPool} 复用 */
public class ReplayEngine {

    private final String jdbcUrl;
    private final String lookupUser;
    private final String lookupPass;
    private final Map<String, String[]> maps;
    private final boolean schemaViaAlter;
    private final LineOut out;
    private final JdbcPool pool;
    private final boolean ownsPool;
    /** JDBC Statement.setQueryTimeout 秒数; &lt;=0 不限制 */
    private int queryTimeoutSec = 0;
    /** 指纹不一致时是否阻断回放; true=fail (默认), false=WARN 后继续 */
    private boolean shaMismatchFail = true;
    private ReplayResultCsv resultCsv;
    private final ThreadLocal<RowCtx> rowCtx = new ThreadLocal<RowCtx>();

    private static final class RowCtx {
        final String sqlId;
        final int child;
        final int instId;

        RowCtx(String sqlId, int child, int instId) {
            this.sqlId = sqlId == null ? "" : sqlId;
            this.child = child;
            this.instId = instId;
        }
    }

    /** 行输出回调 */
    public interface LineOut {
        void println(String line);
    }

    public ReplayEngine(String jdbcUrl, String lookupUser, String lookupPass,
                        Map<String, String[]> maps, boolean schemaViaAlter, LineOut out) {
        this(jdbcUrl, lookupUser, lookupPass, maps, schemaViaAlter, out, null);
    }

    public ReplayEngine(String jdbcUrl, String lookupUser, String lookupPass,
                        Map<String, String[]> maps, boolean schemaViaAlter, LineOut out,
                        JdbcPool pool) {
        this.jdbcUrl = jdbcUrl;
        this.lookupUser = lookupUser;
        this.lookupPass = lookupPass;
        this.maps = maps == null ? new HashMap<String, String[]>() : maps;
        this.schemaViaAlter = schemaViaAlter;
        this.out = out == null ? new LineOut() {
            public void println(String line) {
                System.out.println(line);
            }
        } : out;
        if (pool != null) {
            this.pool = pool;
            this.ownsPool = false;
        } else {
            this.pool = new JdbcPool(null, JdbcPool.DEFAULT_MAX_IDLE_PER_USER);
            this.ownsPool = true;
        }
    }

    public void setQueryTimeoutSec(int sec) {
        this.queryTimeoutSec = sec < 0 ? 0 : sec;
    }

    public int getQueryTimeoutSec() {
        return queryTimeoutSec;
    }

    /** true=指纹失败阻断回放 (默认); false=WARN 后继续回放 */
    public void setShaMismatchFail(boolean fail) {
        this.shaMismatchFail = fail;
    }

    public boolean isShaMismatchFail() {
        return shaMismatchFail;
    }

    public void setResultCsv(ReplayResultCsv csv) {
        this.resultCsv = csv;
    }

    public void beginRow(String sqlId, int child, int instId) {
        rowCtx.set(new RowCtx(sqlId, child, instId));
    }

    public void endRow() {
        rowCtx.remove();
    }

    /** 关闭引擎自建池; 外部传入的共享池不在此关闭 */
    public void close() {
        if (ownsPool && pool != null) {
            pool.close();
        }
    }

    private void applyQueryTimeout(Statement st) throws SQLException {
        if (queryTimeoutSec > 0 && st != null) {
            st.setQueryTimeout(queryTimeoutSec);
        }
    }

    public static Map<String, String[]> mapsFromConfig(Map<String, String[]> cfgMaps) {
        Map<String, String[]> m = new HashMap<String, String[]>();
        if (cfgMaps != null) {
            m.putAll(cfgMaps);
        }
        return m;
    }

    public static Map<String, String[]> loadUserMapsFile(String path) throws IOException {
        Map<String, String[]> maps = new HashMap<String, String[]>();
        if (path == null || path.isEmpty() || "-".equals(path) || !Files.exists(Paths.get(path))) {
            return maps;
        }
        for (String ln : readFile(path).split("\n", -1)) {
            if (ln.isEmpty() || ln.startsWith("#")) {
                continue;
            }
            String[] p = PipeEscape.split(ln, 3);
            if (p.length < 3) {
                continue;
            }
            String schema = p[0].trim().toUpperCase(Locale.ROOT);
            if (schema.isEmpty()) {
                continue;
            }
            maps.put(schema, new String[] {p[1].trim(), p[2]});
        }
        return maps;
    }

    public ReplayResult replayFile(String schema, String sqlFile, String bindsFile,
                                   String mode, boolean force) throws Exception {
        return replayFile(schema, sqlFile, bindsFile, mode, force, "", 0, 1, null);
    }

    public ReplayResult replayFile(String schema, String sqlFile, String bindsFile,
                                   String mode, boolean force,
                                   String sqlId, int child, int instId) throws Exception {
        return replayFile(schema, sqlFile, bindsFile, mode, force, sqlId, child, instId, null);
    }

    public ReplayResult replayFile(String schema, String sqlFile, String bindsFile,
                                   String mode, boolean force,
                                   String sqlId, int child, int instId,
                                   String expectedSqlSha256) throws Exception {
        beginRow(sqlId, child, instId);
        try {
            String sql = readFile(sqlFile);
            if (!assertSqlSha256(sql, expectedSqlSha256, "file")) {
                ReplayResult r = new ReplayResult(0, 1);
                out.println("replay summary ok=" + r.ok + " fail=" + r.fail);
                return r;
            }
            List<String[]> binds = readBinds(bindsFile);
            out.println("replay source=file");
            String[] cred = resolveExecCreds(schema);
            out.println("replay login-user=" + cred[0] + ("dry".equalsIgnoreCase(mode) ? " (planned)" : ""));
            boolean ok;
            if ("dry".equalsIgnoreCase(mode)) {
                ok = execSql(null, schema, sql, binds, mode, force, null);
            } else {
                Connection c = connectAs(cred[0], cred[1]);
                try {
                    ok = execSql(c, schema, sql, binds, mode, force, cred[0]);
                } finally {
                    c.close();
                }
            }
            ReplayResult r = new ReplayResult(ok ? 1 : 0, ok ? 0 : 1);
            out.println("replay summary ok=" + r.ok + " fail=" + r.fail);
            return r;
        } finally {
            endRow();
        }
    }

    public ReplayResult replayGv(String sqlId, String mode, boolean force) throws Exception {
        String schema = null;
        int child = 0;
        int instId = 1;
        String sql = null;
        List<String[]> binds = new ArrayList<String[]>();
        Connection cLookup = connectAs(lookupUser, lookupPass);
        out.println("replay lookup-user=" + lookupUser);
        try {
            try (PreparedStatement ps = cLookup.prepareStatement(
                    "SELECT parsing_schema_name, child_number, NVL(inst_id,1), sql_fulltext FROM ("
                            + " SELECT parsing_schema_name, child_number, inst_id, sql_fulltext"
                            + "   FROM gv$sql WHERE sql_id = ?"
                            + "  ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number"
                            + ") WHERE ROWNUM = 1")) {
                ps.setString(1, sqlId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        schema = rs.getString(1);
                        child = rs.getInt(2);
                        instId = rs.getInt(3);
                        sql = JdbcSession.readClob(rs.getClob(4));
                    }
                }
            } catch (SQLException e) {
                out.println("replay warn gv$sql " + e.getMessage());
            }
            if (sql == null) {
                try (PreparedStatement ps = cLookup.prepareStatement(
                        "SELECT parsing_schema_name, child_number, sql_fulltext FROM ("
                                + " SELECT parsing_schema_name, child_number, sql_fulltext"
                                + "   FROM v$sql WHERE sql_id = ?"
                                + "  ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number"
                                + ") WHERE ROWNUM = 1")) {
                    ps.setString(1, sqlId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (!rs.next()) {
                            out.println("replay fail sql_id not found in gv$/v$sql: " + sqlId);
                            return new ReplayResult(0, 1);
                        }
                        schema = rs.getString(1);
                        child = rs.getInt(2);
                        instId = 1;
                        sql = JdbcSession.readClob(rs.getClob(3));
                    }
                }
            }
            out.println("replay source=gv sql_id=" + sqlId + " child=" + child + " inst_id=" + instId);
            // gv 无采集快照指纹: 仅审计打印, 不做 mismatch 硬失败
            out.println("replay sql_sha256=" + ReplayPackageMeta.sha256Utf8(sql) + " (gv live; no package fingerprint)");
            binds = loadGvBinds(cLookup, sqlId, child, instId);
            String kind = classifySql(sql);
            String[] cred = resolveExecCreds(schema);
            if ("dry".equalsIgnoreCase(mode) || (!force && !"query".equals(kind))) {
                out.println("replay login-user=" + cred[0] + " (planned)");
                beginRow(sqlId, child, instId);
                try {
                    boolean okDry = execSql(null, schema, sql, binds, mode, force, null);
                    ReplayResult r = new ReplayResult(okDry ? 1 : 0, okDry ? 0 : 1);
                    out.println("replay summary ok=" + r.ok + " fail=" + r.fail);
                    return r;
                } finally {
                    endRow();
                }
            }
        } finally {
            cLookup.close();
        }
        String[] cred = resolveExecCreds(schema);
        Connection cExec = connectAs(cred[0], cred[1]);
        boolean okExec;
        beginRow(sqlId, child, instId);
        try {
            okExec = execSql(cExec, schema, sql, binds, mode, force, cred[0]);
        } finally {
            endRow();
            cExec.close();
        }
        ReplayResult r = new ReplayResult(okExec ? 1 : 0, okExec ? 0 : 1);
        out.println("replay summary ok=" + r.ok + " fail=" + r.fail);
        return r;
    }

    public ReplayResult replayHtzOne(String sqlId, String mode, boolean force) throws Exception {
        Connection cLookup = connectAs(lookupUser, lookupPass);
        out.println("replay lookup-user=" + lookupUser);
        List<Object[]> rows = new ArrayList<Object[]>();
        try {
            rows = loadHtzRows(cLookup, sqlId);
        } finally {
            cLookup.close();
        }
        if (rows.isEmpty()) {
            out.println("replay fail sql_id not found in HTZ_SQL_REPLAY_PKG: " + sqlId);
            return new ReplayResult(0, 1);
        }
        int okN = 0;
        int failN = 0;
        for (Object[] row : rows) {
            int child = ((Integer) row[0]).intValue();
            int instId = ((Integer) row[1]).intValue();
            String schema = (String) row[2];
            String sql = (String) row[3];
            String bj = (String) row[4];
            String sha = (String) row[5];
            out.println("replay source=htz sql_id=" + sqlId + " child=" + child
                    + " inst_id=" + instId);
            if (!assertSqlSha256(sql, sha, "htz")) {
                failN++;
                continue;
            }
            List<String[]> binds = JsonBinds.toReplayRows(JsonBinds.read(bj));
            beginRow(sqlId, child, instId);
            try {
                ReplayResult r = execOne(schema, sql, binds, mode, force);
                okN += r.ok;
                failN += r.fail;
            } catch (Exception e) {
                out.println("replay fail " + e.getMessage());
                failN++;
            } finally {
                endRow();
            }
        }
        out.println("replay summary ok=" + okN + " fail=" + failN);
        return new ReplayResult(okN, failN);
    }

    public ReplayResult replayHtzAll(String mode, boolean force) throws Exception {
        Connection cLookup = connectAs(lookupUser, lookupPass);
        out.println("replay lookup-user=" + lookupUser);
        List<Object[]> rows = new ArrayList<Object[]>();
        try {
            rows = loadHtzRows(cLookup, null);
        } finally {
            cLookup.close();
        }
        if (rows.isEmpty()) {
            out.println("replay fail HTZ_SQL_REPLAY_PKG is empty");
            return new ReplayResult(0, 1);
        }
        int okN = 0;
        int failN = 0;
        for (Object[] row : rows) {
            String sqlId = (String) row[0];
            int child = ((Integer) row[1]).intValue();
            int instId = ((Integer) row[2]).intValue();
            String schema = (String) row[3];
            String sql = (String) row[4];
            String bj = (String) row[5];
            String sha = (String) row[6];
            out.println("replay source=htz sql_id=" + sqlId + " child=" + child
                    + " inst_id=" + instId);
            if (!assertSqlSha256(sql, sha, "htz")) {
                failN++;
                continue;
            }
            List<String[]> binds = JsonBinds.toReplayRows(JsonBinds.read(bj));
            beginRow(sqlId, child, instId);
            try {
                ReplayResult r = execOne(schema, sql, binds, mode, force);
                okN += r.ok;
                failN += r.fail;
            } catch (Exception e) {
                out.println("replay fail " + e.getMessage());
                failN++;
            } finally {
                endRow();
            }
        }
        out.println("replay summary ok=" + okN + " fail=" + failN);
        return new ReplayResult(okN, failN);
    }

    /**
     * 加载 HTZ 行. sqlId 非空则按 id 过滤.
     * 行布局: 有 sqlId 时 [child,inst,schema,sql,binds,sha];
     * 全表时 [sqlId,child,inst,schema,sql,binds,sha].
     */
    private List<Object[]> loadHtzRows(Connection cLookup, String sqlId) throws SQLException {
        List<Object[]> rows = new ArrayList<Object[]>();
        String qn = HtzTables.qname(lookupUser, HtzTables.REPLAY_PKG);
        boolean withSha = true;
        String baseCols = "child_number, NVL(inst_id,1), parsing_schema, sql_fulltext, binds_json";
        String colsSha = baseCols + ", sql_sha256";
        try {
            if (sqlId != null) {
                try (PreparedStatement ps = cLookup.prepareStatement(
                        "SELECT " + colsSha + " FROM " + qn
                                + " WHERE sql_id = ? ORDER BY child_number, inst_id")) {
                    ps.setString(1, sqlId);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            rows.add(new Object[] {
                                Integer.valueOf(rs.getInt(1)),
                                Integer.valueOf(rs.getInt(2)),
                                rs.getString(3),
                                JdbcSession.readClob(rs.getClob(4)),
                                JdbcSession.readClob(rs.getClob(5)),
                                rs.getString(6)
                            });
                        }
                    }
                }
            } else {
                try (Statement st = cLookup.createStatement();
                     ResultSet rs = st.executeQuery(
                             "SELECT sql_id, " + colsSha + " FROM " + qn
                                     + " ORDER BY sql_id, child_number, inst_id")) {
                    while (rs.next()) {
                        rows.add(new Object[] {
                            rs.getString(1),
                            Integer.valueOf(rs.getInt(2)),
                            Integer.valueOf(rs.getInt(3)),
                            rs.getString(4),
                            JdbcSession.readClob(rs.getClob(5)),
                            JdbcSession.readClob(rs.getClob(6)),
                            rs.getString(7)
                        });
                    }
                }
            }
        } catch (SQLException e) {
            withSha = false;
            out.println("replay warn HTZ sql_sha256 column unavailable: " + e.getMessage());
            rows.clear();
            if (sqlId != null) {
                try (PreparedStatement ps = cLookup.prepareStatement(
                        "SELECT " + baseCols + " FROM " + qn
                                + " WHERE sql_id = ? ORDER BY child_number, inst_id")) {
                    ps.setString(1, sqlId);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            rows.add(new Object[] {
                                Integer.valueOf(rs.getInt(1)),
                                Integer.valueOf(rs.getInt(2)),
                                rs.getString(3),
                                JdbcSession.readClob(rs.getClob(4)),
                                JdbcSession.readClob(rs.getClob(5)),
                                null
                            });
                        }
                    }
                }
            } else {
                try (Statement st = cLookup.createStatement();
                     ResultSet rs = st.executeQuery(
                             "SELECT sql_id, " + baseCols + " FROM " + qn
                                     + " ORDER BY sql_id, child_number, inst_id")) {
                    while (rs.next()) {
                        rows.add(new Object[] {
                            rs.getString(1),
                            Integer.valueOf(rs.getInt(2)),
                            Integer.valueOf(rs.getInt(3)),
                            rs.getString(4),
                            JdbcSession.readClob(rs.getClob(5)),
                            JdbcSession.readClob(rs.getClob(6)),
                            null
                        });
                    }
                }
            }
        }
        if (!withSha) {
            out.println("replay warn sql_sha256 hard-check skipped for HTZ (legacy table)");
        }
        return rows;
    }

    /** SQL 文本指纹校验; expected 空则仅审计 (legacy).
     *  mismatch 时: shaMismatchFail=true 阻断; false 则 WARN 后仍允许回放. */
    private boolean assertSqlSha256(String sql, String expectedSha, String where) {
        String actual = ReplayPackageMeta.sha256Utf8(sql);
        out.println("replay sql_sha256=" + actual + " source=" + where);
        String reason = ReplayPackageMeta.mismatchReason(sql, expectedSha);
        if (reason == null) {
            if (expectedSha != null && !expectedSha.trim().isEmpty()) {
                out.println("replay sql_sha256 ok");
            } else {
                out.println("replay warn sql_sha256 missing (" + where
                        + "); skip hard check (legacy package)");
            }
            return true;
        }
        if (shaMismatchFail) {
            out.println("replay fail " + reason + " (" + where + "; on-sha-mismatch=fail)");
            return false;
        }
        out.println("replay warn " + reason + " (" + where
                + "; on-sha-mismatch=warn; continue replay)");
        return true;
    }

    private ReplayResult execOne(String schema, String sql, List<String[]> binds, String mode, boolean force)
            throws Exception {
        String kind = classifySql(sql);
        String[] cred = resolveExecCreds(schema);
        boolean ok;
        if ("dry".equalsIgnoreCase(mode) || (!force && !"query".equals(kind))) {
            out.println("replay login-user=" + cred[0] + " (planned)");
            ok = execSql(null, schema, sql, binds, mode, force, null);
        } else {
            Connection cExec = connectAs(cred[0], cred[1]);
            try {
                ok = execSql(cExec, schema, sql, binds, mode, force, cred[0]);
            } finally {
                cExec.close();
            }
        }
        return new ReplayResult(ok ? 1 : 0, ok ? 0 : 1);
    }

    private List<String[]> loadGvBinds(Connection c, String sqlId, int child, int instId) {
        List<String[]> binds = new ArrayList<String[]>();
        boolean got = false;
        try (PreparedStatement ps = c.prepareStatement(
                "SELECT position, datatype_string, value_string FROM gv$sql_bind_capture"
                        + " WHERE sql_id = ? AND child_number = ? AND inst_id = ?"
                        + " ORDER BY position, name")) {
            ps.setString(1, sqlId);
            ps.setInt(2, child);
            ps.setInt(3, instId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    got = true;
                    String val = rs.getString(3);
                    binds.add(new String[] {
                        String.valueOf(rs.getInt(1)),
                        rs.getString(2) == null ? "" : rs.getString(2),
                        val == null ? "" : val
                    });
                }
            }
        } catch (SQLException e) {
            out.println("replay warn gv$sql_bind_capture " + e.getMessage());
        }
        if (!got) {
            try (PreparedStatement ps = c.prepareStatement(
                    "SELECT position, datatype_string, value_string FROM v$sql_bind_capture"
                            + " WHERE sql_id = ? AND child_number = ? ORDER BY position, name")) {
                ps.setString(1, sqlId);
                ps.setInt(2, child);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        String val = rs.getString(3);
                        binds.add(new String[] {
                            String.valueOf(rs.getInt(1)),
                            rs.getString(2) == null ? "" : rs.getString(2),
                            val == null ? "" : val
                        });
                    }
                }
            } catch (SQLException e) {
                out.println("replay warn bind_capture " + e.getMessage());
            }
        }
        return binds;
    }

    private Connection connectAs(String user, String pass) throws SQLException {
        out.println("replay login-user=" + user);
        return pool.borrow(jdbcUrl, user, pass);
    }

    String[] resolveExecCreds(String schema) {
        if (schemaViaAlter) {
            out.println("replay login-mode=alter-session user=" + lookupUser);
            return new String[] {lookupUser, lookupPass};
        }
        if (schema != null && !schema.isEmpty() && !"NULL".equalsIgnoreCase(schema)) {
            String key = schema.toUpperCase(Locale.ROOT);
            if (maps.containsKey(key)) {
                String[] c = maps.get(key);
                out.println("replay map-hit schema=" + key + " user=" + c[0]);
                return c;
            }
            out.println("replay warn no [map." + key + "] in ini; try schema user + default password");
            return new String[] {schema, lookupPass};
        }
        out.println("replay warn empty parsing_schema; fallback lookup user");
        return new String[] {lookupUser, lookupPass};
    }

    private boolean execSql(Connection c, String schema, String sql, List<String[]> binds,
                            String mode, boolean force, String loginUser) throws Exception {
        long t0 = System.currentTimeMillis();
        out.println("replay sql-chars=" + (sql == null ? 0 : sql.length()));
        out.println("replay binds=" + binds.size());
        out.println("replay schema=" + (schema == null ? "" : schema));
        String kind = classifySql(sql);
        out.println("replay sql-kind=" + kind);
        int empty = 0;
        for (String[] b : binds) {
            if (b[2] == null || b[2].isEmpty()) {
                empty++;
            }
        }
        if (empty > 0) {
            out.println("replay warn empty_bind_values=" + empty);
        }
        if (!force && !"query".equals(kind)) {
            out.println("replay blocked kind=" + kind + " (query-only; pass --force to allow)");
            if ("dry".equalsIgnoreCase(mode)) {
                out.println("replay dry-run-ok");
                recordResult(schema, kind, 0, System.currentTimeMillis() - t0, "dry", "blocked_dry");
                return true;
            }
            out.println("replay fail blocked non-query without --force");
            recordResult(schema, kind, 1, System.currentTimeMillis() - t0, "", "blocked");
            return false;
        }
        if ("dry".equalsIgnoreCase(mode)) {
            out.println("replay dry-run-ok");
            recordResult(schema, kind, 0, System.currentTimeMillis() - t0, "dry", "");
            return true;
        }
        if (schema != null && !schema.isEmpty() && !"NULL".equalsIgnoreCase(schema)) {
            String login = loginUser;
            if ((login == null || login.isEmpty()) && c != null) {
                try {
                    login = c.getMetaData().getUserName();
                } catch (Exception ignored) {
                }
            }
            if (login != null && login.equalsIgnoreCase(schema)) {
                out.println("replay schema-skip same_as_login=" + schema);
            } else {
                try (Statement st = c.createStatement()) {
                    applyQueryTimeout(st);
                    String q = schema.replace("\"", "\"\"");
                    st.execute("ALTER SESSION SET CURRENT_SCHEMA = \"" + q + "\"");
                    out.println("replay schema-set=" + schema);
                } catch (Exception e) {
                    out.println("replay warn set_schema " + e.getMessage());
                    out.println("replay fail set_schema failed for " + schema);
                    recordResult(schema, kind, 1, System.currentTimeMillis() - t0, "", "set_schema");
                    return false;
                }
            }
        }
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            applyQueryTimeout(ps);
            for (String[] b : binds) {
                int pos;
                try {
                    pos = Integer.parseInt(b[0].trim());
                } catch (NumberFormatException e) {
                    out.println("replay warn skip bad bind position: " + b[0]);
                    continue;
                }
                bindOne(ps, pos, b[1], b[2]);
            }
            boolean hasRs = ps.execute();
            String rowsOrUc;
            if (hasRs) {
                try (ResultSet rs = ps.getResultSet()) {
                    int cols = rs.getMetaData().getColumnCount();
                    int rows = 0;
                    while (rs.next() && rows < 20) {
                        StringBuilder sb = new StringBuilder();
                        for (int i = 1; i <= cols; i++) {
                            if (i > 1) {
                                sb.append("|");
                            }
                            sb.append(rs.getString(i));
                        }
                        out.println("replay row " + sb.toString());
                        rows++;
                    }
                    out.println("replay rows-shown=" + rows);
                    rowsOrUc = String.valueOf(rows);
                }
            } else {
                int uc = ps.getUpdateCount();
                out.println("replay update-count=" + uc);
                rowsOrUc = String.valueOf(uc);
            }
            out.println("replay exec-ok");
            recordResult(schema, kind, 0, System.currentTimeMillis() - t0, rowsOrUc, "");
            return true;
        } catch (Exception e) {
            recordResult(schema, kind, 1, System.currentTimeMillis() - t0, "",
                    e.getClass().getSimpleName());
            throw e;
        }
    }

    private void recordResult(String schema, String kind, int rc, long elapsedMs,
                              String rowsOrUc, String errorClass) {
        if (resultCsv == null) {
            return;
        }
        RowCtx ctx = rowCtx.get();
        String sid = ctx == null ? "" : ctx.sqlId;
        int child = ctx == null ? 0 : ctx.child;
        int instId = ctx == null ? 0 : ctx.instId;
        resultCsv.append(sid, child, instId, schema, kind, rc, elapsedMs, rowsOrUc, errorClass);
    }

    public static class ReplayResult {
        public final int ok;
        public final int fail;

        public ReplayResult(int ok, int fail) {
            this.ok = ok;
            this.fail = fail;
        }

        public boolean success() {
            return fail == 0;
        }
    }

    private static void bindOne(PreparedStatement ps, int idx, String dt, String val) throws SQLException {
        String u = dt == null ? "" : dt.toUpperCase(Locale.ROOT);
        if (val == null || val.isEmpty() || val.equals("\\N")) {
            ps.setNull(idx, nullSqlType(dt));
            return;
        }
        if (u.contains("NUMBER") || u.contains("DECIMAL") || u.contains("INT")
                || u.contains("FLOAT") || u.contains("DOUBLE") || u.contains("BINARY_")) {
            try {
                ps.setBigDecimal(idx, new BigDecimal(val.trim()));
                return;
            } catch (Exception e) {
                ps.setString(idx, val);
                return;
            }
        }
        if (u.contains("DATE") || u.contains("TIMESTAMP") || u.contains("TIME")) {
            String t = val.trim();
            String[] patterns = new String[] {
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss.SSS",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd HH:mm",
                "yyyy-MM-dd",
                "yyyy/MM/dd HH:mm:ss",
                "yyyy/MM/dd",
                "dd-MMM-yy",
                "dd-MMM-yyyy"
            };
            for (String pattern : patterns) {
                try {
                    java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat(pattern, Locale.US);
                    sdf.setLenient(false);
                    java.util.Date d = sdf.parse(t);
                    if (u.contains("DATE") && !u.contains("TIMESTAMP") && "yyyy-MM-dd".equals(pattern)) {
                        ps.setDate(idx, new java.sql.Date(d.getTime()));
                    } else {
                        ps.setTimestamp(idx, new Timestamp(d.getTime()));
                    }
                    return;
                } catch (Exception ignored) {
                }
            }
            throw new SQLException("unparsed date/timestamp bind value: " + val);
        }
        ps.setString(idx, val);
    }

    private static int nullSqlType(String dt) {
        String u = dt == null ? "" : dt.toUpperCase(Locale.ROOT);
        if (u.contains("NUMBER") || u.contains("DECIMAL") || u.contains("INT")
                || u.contains("FLOAT") || u.contains("DOUBLE") || u.contains("BINARY_")) {
            return Types.NUMERIC;
        }
        if (u.contains("TIMESTAMP") || u.contains("TIME")) {
            return Types.TIMESTAMP;
        }
        if (u.contains("DATE")) {
            return Types.DATE;
        }
        return Types.VARCHAR;
    }

    static String classifySql(String sql) {
        String s = stripSqlLead(sql);
        if (s.isEmpty()) {
            return "empty";
        }
        String u = s.toUpperCase(Locale.ROOT);
        if (u.startsWith("WITH")) {
            Matcher m = Pattern.compile("\\b(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE)\\b").matcher(u);
            if (m.find()) {
                String k = m.group(1);
                if ("CREATE".equals(k) || "ALTER".equals(k) || "DROP".equals(k) || "TRUNCATE".equals(k)) {
                    return "ddl";
                }
                return "dml";
            }
            return "query";
        }
        if (u.startsWith("SELECT") || u.startsWith("EXPLAIN")) {
            return "query";
        }
        if (u.startsWith("INSERT") || u.startsWith("UPDATE") || u.startsWith("DELETE") || u.startsWith("MERGE")) {
            return "dml";
        }
        if (u.startsWith("CREATE") || u.startsWith("ALTER") || u.startsWith("DROP") || u.startsWith("TRUNCATE")
                || u.startsWith("GRANT") || u.startsWith("REVOKE") || u.startsWith("COMMENT")
                || u.startsWith("ANALYZE") || u.startsWith("FLASHBACK") || u.startsWith("PURGE")
                || u.startsWith("RENAME")) {
            return "ddl";
        }
        if (u.startsWith("BEGIN") || u.startsWith("DECLARE") || u.startsWith("CALL") || u.startsWith("EXEC")) {
            return "plsql";
        }
        return "other";
    }

    /** 引号感知剥离行注释; 供 classifySql 使用 (不影响实际执行文本) */
    static String stripSqlLead(String sql) {
        if (sql == null) {
            return "";
        }
        String s = sql.replaceAll("/\\*[\\s\\S]*?\\*/", " ");
        StringBuilder sb = new StringBuilder();
        for (String ln : s.split("\n", -1)) {
            sb.append(stripLineComment(ln)).append('\n');
        }
        s = sb.toString().trim();
        while (s.startsWith("(")) {
            s = s.substring(1).trim();
        }
        return s;
    }

    private static String stripLineComment(String ln) {
        boolean inStr = false;
        for (int i = 0; i < ln.length(); i++) {
            char c = ln.charAt(i);
            if (inStr) {
                if (c == '\'') {
                    if (i + 1 < ln.length() && ln.charAt(i + 1) == '\'') {
                        i++;
                    } else {
                        inStr = false;
                    }
                }
                continue;
            }
            if (c == '\'') {
                inStr = true;
                continue;
            }
            if (c == '-' && i + 1 < ln.length() && ln.charAt(i + 1) == '-') {
                return ln.substring(0, i);
            }
        }
        return ln;
    }

    private static List<String[]> readBinds(String path) throws IOException {
        List<String[]> out = new ArrayList<String[]>();
        if (path == null || path.isEmpty() || !Files.exists(Paths.get(path))) {
            return out;
        }
        for (String ln : readFile(path).split("\n", -1)) {
            if (ln.isEmpty() || ln.startsWith("#")) {
                continue;
            }
            String[] p = PipeEscape.split(ln, 3);
            if (p.length < 1) {
                continue;
            }
            String pos = p[0].trim();
            if (!pos.matches("\\d+")) {
                System.err.println("WARN: skip binds.txt line (bad position): " + ln);
                continue;
            }
            out.add(new String[] {
                pos,
                p.length > 1 ? p[1].trim() : "VARCHAR2",
                p.length > 2 ? p[2] : ""
            });
        }
        return out;
    }

    private static String readFile(String path) throws IOException {
        byte[] b = Files.readAllBytes(Paths.get(path));
        return new String(b, StandardCharsets.UTF_8);
    }
}
