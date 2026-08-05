package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.db.HtzTables;
import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.model.BindValue;
import com.yashan.sqlcollect.model.ReplayPackageMeta;
import com.yashan.sqlcollect.util.JsonBinds;
import com.yashan.sqlcollect.util.PipeEscape;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

/**
 * 导出 replay 包并 upsert 登录用户下的 HTZ_SQL_REPLAY_PKG.
 * HTZ 表操作失败直接抛错, 由 collect 退出.
 */
public class PackageExporter {

    public static final String REPLAY_DIR = "replay";

    private final DualLogger log;
    private final String owner;

    public PackageExporter(DualLogger log, String jdbcUser) {
        this.log = log;
        this.owner = HtzTables.normalizeOwner(jdbcUser);
    }

    /**
     * 导出 replay 包并 upsert HTZ.
     * @return 包目录路径; sql 不在 v$/gv$sql 时返回 null
     */
    public Path export(JdbcSession session, String sqlId, Path outdir, String kind) throws SQLException {
        log.logStep("replay_export", sqlId + " kind=" + kind + " owner=" + owner);
        Row row = loadLatestRow(session.getConnection(), sqlId);
        if (row == null) {
            log.logWarn("replay export: sql_id not in v$/gv$sql: " + sqlId);
            return null;
        }
        Path pkg;
        try {
            pkg = writeFiles(outdir, row);
        } catch (IOException e) {
            log.logError("write replay package failed for " + sqlId + ": " + e.getMessage());
            throw new SQLException("write replay package failed for " + sqlId, e);
        }
        ensureReplayTable(session.getConnection());
        ensureSqlSha256Column(session.getConnection());
        upsertHtz(session.getConnection(), row);

        String tag = "REFRESH".equalsIgnoreCase(kind) ? "refresh" : "new";
        log.logDbg(String.format("%s export sql_id=%s child=%d inst_id=%d len=%d binds=%d -> %s",
                tag, sqlId, row.meta.childNumber, row.meta.instId, row.meta.sqlLen, row.binds.size(),
                pkg));
        int empty = 0;
        for (BindValue b : row.binds) {
            if (b.value == null || b.value.isEmpty() || "\\N".equals(b.value)) {
                empty++;
            }
        }
        if (empty > 0) {
            log.logWarn(empty + " bind(s) have empty value_string; edit binds.txt before execute");
        }
        return pkg;
    }

    private static class Row {
        ReplayPackageMeta meta = new ReplayPackageMeta();
        String sqlText = "";
        List<BindValue> binds = new ArrayList<BindValue>();
    }

    private Row loadLatestRow(Connection c, String sqlId) throws SQLException {
        String[] queries = new String[] {
            "SELECT child_number, parsing_schema_name, NVL(inst_id,1), hash_value, "
                    + "DBMS_LOB.GETLENGTH(sql_fulltext), sql_fulltext "
                    + "FROM (SELECT child_number, parsing_schema_name, inst_id, hash_value, sql_fulltext, "
                    + "last_active_time, executions FROM gv$sql WHERE sql_id = ? "
                    + "ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number) "
                    + "WHERE ROWNUM = 1",
            "SELECT child_number, parsing_schema_name, 1, hash_value, "
                    + "DBMS_LOB.GETLENGTH(sql_fulltext), sql_fulltext "
                    + "FROM (SELECT child_number, parsing_schema_name, hash_value, sql_fulltext, "
                    + "last_active_time, executions FROM v$sql WHERE sql_id = ? "
                    + "ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number) "
                    + "WHERE ROWNUM = 1"
        };
        Row row = null;
        for (String q : queries) {
            log.logDbg("jdbc sql [export_load]: " + q);
            try (PreparedStatement ps = c.prepareStatement(q)) {
                ps.setString(1, sqlId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        row = new Row();
                        row.meta.sqlId = sqlId;
                        row.meta.childNumber = rs.getInt(1);
                        row.meta.parsingSchema = rs.getString(2);
                        row.meta.instId = rs.getInt(3);
                        row.meta.hashValue = rs.getLong(4);
                        row.meta.sqlLen = rs.getInt(5);
                        row.sqlText = JdbcSession.readClob(rs.getClob(6));
                    }
                }
                if (row != null) {
                    break;
                }
            } catch (SQLException e) {
                log.logDbg("export load sql from alternate view: " + e.getMessage());
            }
        }
        if (row == null) {
            return null;
        }
        row.binds = loadBinds(c, sqlId, row.meta.childNumber, row.meta.instId);
        return row;
    }

    private List<BindValue> loadBinds(Connection c, String sqlId, int child, int instId) throws SQLException {
        List<BindValue> binds = new ArrayList<BindValue>();
        String[] queries = new String[] {
            "SELECT position, name, datatype_string, value_string, was_captured "
                    + "FROM gv$sql_bind_capture WHERE sql_id = ? AND child_number = ? AND inst_id = ? "
                    + "ORDER BY position, name",
            "SELECT position, name, datatype_string, value_string, was_captured "
                    + "FROM v$sql_bind_capture WHERE sql_id = ? AND child_number = ? "
                    + "ORDER BY position, name"
        };
        for (int qi = 0; qi < queries.length; qi++) {
            try (PreparedStatement ps = c.prepareStatement(queries[qi])) {
                log.logDbg("jdbc sql [export_binds]: " + queries[qi]);
                ps.setString(1, sqlId);
                ps.setInt(2, child);
                if (qi == 0) {
                    ps.setInt(3, instId);
                }
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        BindValue b = new BindValue();
                        b.position = rs.getInt(1);
                        b.name = nvl(rs.getString(2));
                        b.datatype = nvl(rs.getString(3));
                        b.value = nvl(rs.getString(4));
                        b.wasCaptured = nvl(rs.getString(5));
                        binds.add(b);
                    }
                }
                if (!binds.isEmpty() || qi == queries.length - 1) {
                    return binds;
                }
            } catch (SQLException e) {
                log.logDbg("export binds alternate view: " + e.getMessage());
            }
        }
        return binds;
    }

    private void ensureReplayTable(Connection c) throws SQLException {
        String qn = HtzTables.qname(owner, HtzTables.REPLAY_PKG);
        if (HtzTables.tableExists(c, owner, HtzTables.REPLAY_PKG)) {
            if (pkIncludesInstId(c)) {
                log.logDbg("TABLE " + qn + " exists");
                return;
            }
            // 工具缓存表: 旧 PK 无 INST_ID 时自动重建 (数据可从 replay 目录重导出)
            log.logWarn("TABLE " + qn
                    + " PK missing INST_ID; dropping and recreating with RAC-safe key");
            HtzTables.exec(c, log, "drop_" + HtzTables.REPLAY_PKG, "DROP TABLE " + qn);
        }
        log.logInfo("TABLE " + qn + " creating");
        // DDL 隐式 commit: 须在本连接任何未提交 DML 之前执行 (不变式)
        String who = HtzTables.currentUser(c);
        String ddlBody = "("
                + "SQL_ID VARCHAR2(13) NOT NULL, "
                + "CHILD_NUMBER NUMBER NOT NULL, "
                + "INST_ID NUMBER NOT NULL, "
                + "HASH_VALUE NUMBER, "
                + "PARSING_SCHEMA VARCHAR2(128), "
                + "SQL_FULLTEXT CLOB, "
                + "BINDS_JSON CLOB, "
                + "SQL_LEN NUMBER, "
                + "SQL_SHA256 VARCHAR2(64), "
                + "COLLECT_TIME DATE, "
                + "CONSTRAINT PK_HTZ_SQL_REPLAY_PKG PRIMARY KEY (SQL_ID, CHILD_NUMBER, INST_ID))";
        if (!who.equalsIgnoreCase(owner)) {
            HtzTables.exec(c, log, "create_" + HtzTables.REPLAY_PKG,
                    "CREATE TABLE " + qn + " " + ddlBody);
        } else {
            HtzTables.exec(c, log, "create_" + HtzTables.REPLAY_PKG,
                    "CREATE TABLE " + HtzTables.REPLAY_PKG + " " + ddlBody);
        }
        log.logInfo("TABLE " + qn + " created");
    }

    /** 旧表 PK 无 INST_ID 时拒绝继续写入, 避免 RAC 静默覆盖 */
    private boolean pkIncludesInstId(Connection c) throws SQLException {
        String sql = "SELECT COUNT(*) FROM user_cons_columns cc "
                + "JOIN user_constraints c ON c.constraint_name = cc.constraint_name "
                + "WHERE c.table_name = ? AND c.constraint_type = 'P' AND cc.column_name = 'INST_ID'";
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, HtzTables.REPLAY_PKG);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getInt(1) > 0;
            }
        } catch (SQLException e) {
            log.logWarn("cannot verify " + HtzTables.REPLAY_PKG + " PK columns: " + e.getMessage());
            return true;
        }
    }

    /** 旧表补 SQL_SHA256 列 (SQL Map 一致性指纹) */
    private void ensureSqlSha256Column(Connection c) throws SQLException {
        String qn = HtzTables.qname(owner, HtzTables.REPLAY_PKG);
        if (!HtzTables.tableExists(c, owner, HtzTables.REPLAY_PKG)) {
            return;
        }
        if (columnExists(c, HtzTables.REPLAY_PKG, "SQL_SHA256")) {
            return;
        }
        log.logInfo("TABLE " + qn + " adding column SQL_SHA256");
        HtzTables.exec(c, log, "alter_add_sql_sha256",
                "ALTER TABLE " + qn + " ADD SQL_SHA256 VARCHAR2(64)");
    }

    private boolean columnExists(Connection c, String table, String column) throws SQLException {
        String sql = "SELECT COUNT(*) FROM user_tab_columns WHERE table_name = ? AND column_name = ?";
        try (PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, table);
            ps.setString(2, column);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return rs.getInt(1) > 0;
            }
        } catch (SQLException e) {
            log.logWarn("cannot verify column " + table + "." + column + ": " + e.getMessage());
            return false;
        }
    }

    private void upsertHtz(Connection c, Row row) throws SQLException {
        String qn = HtzTables.qname(owner, HtzTables.REPLAY_PKG);
        String json = JsonBinds.write(row.binds);
        String sha = ReplayPackageMeta.sha256Utf8(row.sqlText);
        row.meta.sqlSha256 = sha;
        log.logDbg("jdbc upsert " + qn + " sql_id=" + row.meta.sqlId
                + " child=" + row.meta.childNumber + " inst_id=" + row.meta.instId
                + " sql_sha256=" + sha);
        // 逐步 commit: 单 sql_id 的 DELETE+INSERT 原子; 不保证整轮可 rollback
        try (PreparedStatement del = c.prepareStatement(
                "DELETE FROM " + qn + " WHERE sql_id = ? AND child_number = ? AND inst_id = ?")) {
            del.setString(1, row.meta.sqlId);
            del.setInt(2, row.meta.childNumber);
            del.setInt(3, row.meta.instId);
            int dn = del.executeUpdate();
            log.logDbg("jdbc delete " + qn + " rows=" + dn);
        }

        try (PreparedStatement ins = c.prepareStatement(
                "INSERT INTO " + qn + " "
                        + "(sql_id, child_number, inst_id, hash_value, parsing_schema, "
                        + "sql_fulltext, binds_json, sql_len, sql_sha256, collect_time) "
                        + "VALUES (?,?,?,?,?,?,?,?,?,SYSDATE)")) {
            ins.setString(1, row.meta.sqlId);
            ins.setInt(2, row.meta.childNumber);
            ins.setInt(3, row.meta.instId);
            ins.setLong(4, row.meta.hashValue);
            ins.setString(5, row.meta.parsingSchema);
            ins.setString(6, row.sqlText);
            ins.setString(7, json);
            ins.setInt(8, row.meta.sqlLen);
            ins.setString(9, sha);
            ins.executeUpdate();
        }
        c.commit();
        log.logDbg("jdbc insert " + qn + " ok");
    }

    private Path writeFiles(Path outdir, Row row) throws IOException {
        Path pkg = outdir.resolve(REPLAY_DIR).resolve(
                row.meta.sqlId + "__c" + row.meta.childNumber + "__i" + row.meta.instId);
        Files.createDirectories(pkg);
        String sha = ReplayPackageMeta.sha256Utf8(row.sqlText);
        row.meta.sqlSha256 = sha;
        String meta = "sql_id=" + row.meta.sqlId + "\n"
                + "child_number=" + row.meta.childNumber + "\n"
                + "inst_id=" + row.meta.instId + "\n"
                + "hash_value=" + row.meta.hashValue + "\n"
                + "parsing_schema=" + row.meta.parsingSchema + "\n"
                + "sql_len=" + row.meta.sqlLen + "\n"
                + ReplayPackageMeta.META_SQL_SHA256 + "=" + sha + "\n";
        Files.write(pkg.resolve("meta.txt"), meta.getBytes(StandardCharsets.UTF_8));
        Files.write(pkg.resolve("orig.sql"), row.sqlText.getBytes(StandardCharsets.UTF_8));
        // 落盘后立刻回读校验, 防止编码/截断导致与业务 sql_fulltext 不一致
        byte[] written = Files.readAllBytes(pkg.resolve("orig.sql"));
        String roundTrip = new String(written, StandardCharsets.UTF_8);
        if (!row.sqlText.equals(roundTrip)) {
            throw new IOException("orig.sql round-trip mismatch for sql_id=" + row.meta.sqlId
                    + " (in_chars=" + row.sqlText.length() + " out_chars=" + roundTrip.length() + ")");
        }
        String writtenSha = ReplayPackageMeta.sha256Utf8(roundTrip);
        if (!sha.equals(writtenSha)) {
            throw new IOException("orig.sql sha256 mismatch after write for sql_id=" + row.meta.sqlId
                    + " expected=" + sha + " actual=" + writtenSha);
        }
        String json = JsonBinds.write(row.binds);
        Files.write(pkg.resolve("binds.json"), (json + "\n").getBytes(StandardCharsets.UTF_8));
        StringBuilder bt = new StringBuilder("# position|datatype|value\n");
        for (BindValue b : row.binds) {
            bt.append(b.position).append("|")
                    .append(PipeEscape.escape(b.datatype)).append("|")
                    .append(PipeEscape.escape(b.value)).append("\n");
        }
        Files.write(pkg.resolve("binds.txt"), bt.toString().getBytes(StandardCharsets.UTF_8));
        log.logDbg("sql_sha256=" + sha + " sql_id=" + row.meta.sqlId);
        log.logDbg("wrote package files " + pkg);
        return pkg;
    }

    private static String nvl(String s) {
        return s == null ? "" : s;
    }
}
