package com.yashan.sqlcollect.db;

import com.yashan.sqlcollect.model.BindValue;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

/**
 * 从 gv$/v$sql 取 sql_fulltext / hash / schema; 从 bind_capture 取绑定.
 * gv$ 优先, 空/失败回退 v$.
 */
public final class SqlLookup {

    public static final class SqlTextInfo {
        public String sqlText = "";
        public String schema = "";
        public int childNumber;
        public int instId = 1;
        public Long hashValue;
        public boolean found;
    }

    public interface WarnOut {
        void warn(String msg);
    }

    private SqlLookup() {
    }

    public static SqlTextInfo loadSqlText(Connection c, String sqlId, WarnOut warn) {
        SqlTextInfo info = new SqlTextInfo();
        if (c == null || sqlId == null || sqlId.trim().isEmpty()) {
            return info;
        }
        String id = sqlId.trim();
        try (PreparedStatement ps = c.prepareStatement(
                "SELECT parsing_schema_name, child_number, NVL(inst_id,1), sql_fulltext, hash_value FROM ("
                        + " SELECT parsing_schema_name, child_number, inst_id, sql_fulltext, hash_value"
                        + "   FROM gv$sql WHERE sql_id = ?"
                        + "  ORDER BY DBMS_LOB.GETLENGTH(sql_fulltext) DESC NULLS LAST,"
                        + "           last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number"
                        + ") WHERE ROWNUM = 1")) {
            ps.setString(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    fill(info, rs, true);
                    return info;
                }
            }
        } catch (SQLException e) {
            if (warn != null) {
                warn.warn("gv$sql " + e.getMessage());
            }
        }
        try (PreparedStatement ps = c.prepareStatement(
                "SELECT parsing_schema_name, child_number, sql_fulltext, hash_value FROM ("
                        + " SELECT parsing_schema_name, child_number, sql_fulltext, hash_value"
                        + "   FROM v$sql WHERE sql_id = ?"
                        + "  ORDER BY DBMS_LOB.GETLENGTH(sql_fulltext) DESC NULLS LAST,"
                        + "           last_active_time DESC NULLS LAST, executions DESC NULLS LAST, child_number"
                        + ") WHERE ROWNUM = 1")) {
            ps.setString(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    fill(info, rs, false);
                }
            }
        } catch (SQLException e) {
            if (warn != null) {
                warn.warn("v$sql " + e.getMessage());
            }
        }
        return info;
    }

    private static void fill(SqlTextInfo info, ResultSet rs, boolean withInst) throws SQLException {
        info.schema = rs.getString(1);
        info.childNumber = rs.getInt(2);
        int idx = 3;
        if (withInst) {
            info.instId = rs.getInt(idx++);
        } else {
            info.instId = 1;
        }
        info.sqlText = JdbcSession.readClob(rs.getClob(idx++));
        long hv = rs.getLong(idx);
        if (!rs.wasNull()) {
            info.hashValue = Long.valueOf(hv);
        }
        info.found = info.sqlText != null && !info.sqlText.isEmpty();
        if (info.sqlText == null) {
            info.sqlText = "";
        }
    }

    public static List<BindValue> loadBinds(Connection c, String sqlId, int child, int instId,
                                            WarnOut warn) {
        List<BindValue> binds = new ArrayList<BindValue>();
        if (c == null || sqlId == null) {
            return binds;
        }
        boolean got = false;
        try (PreparedStatement ps = c.prepareStatement(
                "SELECT position, name, datatype_string, value_string FROM gv$sql_bind_capture"
                        + " WHERE sql_id = ? AND child_number = ? AND inst_id = ?"
                        + " ORDER BY position, name")) {
            ps.setString(1, sqlId);
            ps.setInt(2, child);
            ps.setInt(3, instId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    got = true;
                    binds.add(row(rs));
                }
            }
        } catch (SQLException e) {
            if (warn != null) {
                warn.warn("gv$sql_bind_capture " + e.getMessage());
            }
        }
        if (!got) {
            try (PreparedStatement ps = c.prepareStatement(
                    "SELECT position, name, datatype_string, value_string FROM v$sql_bind_capture"
                            + " WHERE sql_id = ? AND child_number = ? ORDER BY position, name")) {
                ps.setString(1, sqlId);
                ps.setInt(2, child);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        binds.add(row(rs));
                    }
                }
            } catch (SQLException e) {
                if (warn != null) {
                    warn.warn("v$sql_bind_capture " + e.getMessage());
                }
            }
        }
        return binds;
    }

    /** 仅按 sql_id 取最新 child 的绑定 (export/genbind 便捷). */
    public static List<BindValue> loadBindsBySqlId(Connection c, String sqlId, WarnOut warn) {
        SqlTextInfo info = loadSqlText(c, sqlId, warn);
        if (!info.found) {
            return new ArrayList<BindValue>();
        }
        return loadBinds(c, sqlId, info.childNumber, info.instId, warn);
    }

    public static List<String[]> toReplayRows(List<BindValue> binds) {
        List<String[]> rows = new ArrayList<String[]>();
        if (binds == null) {
            return rows;
        }
        for (BindValue b : binds) {
            rows.add(new String[] {
                String.valueOf(b.position),
                b.datatype == null ? "" : b.datatype,
                b.value == null ? "" : b.value
            });
        }
        return rows;
    }

    private static BindValue row(ResultSet rs) throws SQLException {
        BindValue b = new BindValue();
        b.position = rs.getInt(1);
        String name = rs.getString(2);
        b.name = name == null ? "" : name;
        String dt = rs.getString(3);
        b.datatype = dt == null ? "" : dt;
        String val = rs.getString(4);
        b.value = val == null ? "" : val;
        return b;
    }
}
