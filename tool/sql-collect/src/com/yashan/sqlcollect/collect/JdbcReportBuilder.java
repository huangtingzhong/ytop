package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.db.SqlLookup;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.model.BindValue;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

/**
 * 纯 JDBC 报告构建.
 * ORIGINAL + LITERAL: Java; PLAN/sqlarea/AWR/objects: {@link ReportSelectScript} + JDBC SELECT.
 */
public class JdbcReportBuilder {

    private final DualLogger log;
    private final SqlReportRunner selectSections;
    private boolean explainPlan;

    public JdbcReportBuilder(DualLogger log) {
        this.log = log;
        this.selectSections = new SqlReportRunner(log);
    }

    public void setExplainPlan(boolean explainPlan) {
        this.explainPlan = explainPlan;
    }

    public String build(JdbcSession session, String sqlId, int timeoutSec) throws SQLException {
        long deadlineMs = timeoutSec <= 0
                ? Long.MAX_VALUE
                : System.currentTimeMillis() + (long) timeoutSec * 1000L;
        StringBuilder out = new StringBuilder();
        Connection c = session.getConnection();

        out.append("****************************************************************************************\n");
        out.append("ORIGINAL SQL / LITERAL SQL (JDBC native report)\n");
        out.append("****************************************************************************************\n");
        out.append("sql_id=").append(sqlId == null ? "" : sqlId).append('\n');

        CursorRow row;
        try {
            row = loadCursor(c, sqlId, stmtTimeout(deadlineMs, timeoutSec));
        } catch (SQLException e) {
            out.append("[ERROR] load cursor: ").append(e.getMessage()).append('\n');
            if (log != null) {
                log.logWarn("report load cursor failed sql_id=" + sqlId + ": " + e.getMessage());
            }
            return out.toString();
        }
        if (row == null) {
            out.append("No SQL found in V$SQL for sql_id=").append(sqlId).append('\n');
            return out.toString();
        }

        out.append("===== ORIGINAL SQL =====\n");
        out.append("Schema: ").append(nvl(row.schema))
                .append(" child=").append(row.child)
                .append(" inst_id=").append(row.instId)
                .append(" len=").append(row.sqlText == null ? 0 : row.sqlText.length())
                .append('\n');
        out.append(row.sqlText == null ? "" : row.sqlText);
        if (row.sqlText != null && !row.sqlText.endsWith("\n")) {
            out.append('\n');
        }
        out.append("--------------------------------------------------------\n");

        if (timedOut(deadlineMs)) {
            out.append("[ERROR] report timeout after ").append(timeoutSec).append("s\n");
            return out.toString();
        }

        try {
            List<BindValue> binds = loadBinds(c, sqlId, row.child, row.instId,
                    stmtTimeout(deadlineMs, timeoutSec));
            out.append("===== LITERAL SQL =====\n");
            out.append("Schema: ").append(nvl(row.schema))
                    .append(" child=").append(row.child)
                    .append(" (bind values from capture; Java rewrite)\n");
            if (binds.isEmpty()) {
                out.append("(no bind capture on executed child; same as ORIGINAL SQL)\n");
                out.append(row.sqlText == null ? "" : row.sqlText);
            } else {
                String lit = LiteralBindRewrite.rewrite(row.sqlText, binds);
                out.append(lit);
            }
            if (out.charAt(out.length() - 1) != '\n') {
                out.append('\n');
            }
            out.append("--------------------------------------------------------\n");
        } catch (SQLException e) {
            out.append("[ERROR] literal binds: ").append(e.getMessage()).append('\n');
            if (log != null) {
                log.logWarn("report literal failed sql_id=" + sqlId + ": " + e.getMessage());
            }
        }

        if (timedOut(deadlineMs)) {
            out.append("[ERROR] report timeout after ").append(timeoutSec).append("s\n");
            return out.toString();
        }

        out.append('\n');
        try {
            selectSections.appendFromPlan(session, sqlId, out, deadlineMs, timeoutSec);
        } catch (java.io.IOException e) {
            out.append("[ERROR] P1 sections: ").append(e.getMessage()).append('\n');
            if (log != null) {
                log.logWarn("report P1 failed sql_id=" + sqlId + ": " + e.getMessage());
            }
        } catch (SQLException e) {
            out.append("[ERROR] P1 sections: ").append(e.getMessage()).append('\n');
            if (log != null) {
                log.logWarn("report P1 failed sql_id=" + sqlId + ": " + e.getMessage());
            }
        }

        if (explainPlan && !timedOut(deadlineMs)) {
            ExplainPlanSection.append(c, sqlId, row.sqlText, out, log,
                    stmtTimeout(deadlineMs, timeoutSec));
        }
        return out.toString();
    }

    private static final class CursorRow {
        String schema;
        int child;
        int instId;
        String sqlText;
    }

    private CursorRow loadCursor(Connection c, String sqlId, int qTimeout) throws SQLException {
        SqlLookup.CapturedChild prefer = SqlLookup.pickBestCapturedChild(c, sqlId);
        if (prefer != null) {
            CursorRow byChild = loadCursorByChild(c, sqlId, prefer.childNumber, prefer.instId, qTimeout);
            if (byChild != null) {
                return byChild;
            }
        }
        String[] queries = new String[] {
            "SELECT parsing_schema_name, child_number, NVL(inst_id,1), sql_fulltext FROM ("
                    + " SELECT s.parsing_schema_name, s.child_number, s.inst_id, s.sql_fulltext"
                    + "   FROM gv$sql s WHERE s.sql_id = ?"
                    + "  ORDER BY " + SqlLookup.ORDER_GV_PREFER_CAPTURED
                    + ") WHERE ROWNUM = 1",
            "SELECT parsing_schema_name, child_number, 1, sql_fulltext FROM ("
                    + " SELECT s.parsing_schema_name, s.child_number, s.sql_fulltext"
                    + "   FROM v$sql s WHERE s.sql_id = ?"
                    + "  ORDER BY " + SqlLookup.ORDER_V_PREFER_CAPTURED
                    + ") WHERE ROWNUM = 1"
        };
        for (String q : queries) {
            try (PreparedStatement ps = c.prepareStatement(q)) {
                if (qTimeout > 0) {
                    ps.setQueryTimeout(qTimeout);
                }
                ps.setString(1, sqlId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        continue;
                    }
                    CursorRow row = new CursorRow();
                    row.schema = rs.getString(1);
                    row.child = rs.getInt(2);
                    row.instId = rs.getInt(3);
                    row.sqlText = JdbcSession.readClob(rs.getClob(4));
                    return row;
                }
            } catch (SQLException e) {
                if (log != null) {
                    log.logDbg("report cursor query failed: " + e.getMessage());
                }
            }
        }
        return null;
    }

    private CursorRow loadCursorByChild(Connection c, String sqlId, int child, int instId, int qTimeout)
            throws SQLException {
        String[] queries = new String[] {
            "SELECT parsing_schema_name, child_number, NVL(inst_id,1), sql_fulltext FROM gv$sql "
                    + "WHERE sql_id = ? AND child_number = ? AND NVL(inst_id,1) = ? AND ROWNUM = 1",
            "SELECT parsing_schema_name, child_number, 1, sql_fulltext FROM v$sql "
                    + "WHERE sql_id = ? AND child_number = ? AND ROWNUM = 1",
            "SELECT parsing_schema_name, child_number, NVL(inst_id,1), sql_fulltext FROM gv$sql "
                    + "WHERE sql_id = ? AND child_number = ? AND ROWNUM = 1"
        };
        for (int qi = 0; qi < queries.length; qi++) {
            try (PreparedStatement ps = c.prepareStatement(queries[qi])) {
                if (qTimeout > 0) {
                    ps.setQueryTimeout(qTimeout);
                }
                ps.setString(1, sqlId);
                ps.setInt(2, child);
                if (qi == 0) {
                    ps.setInt(3, instId);
                }
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        continue;
                    }
                    CursorRow row = new CursorRow();
                    row.schema = rs.getString(1);
                    row.child = rs.getInt(2);
                    row.instId = rs.getInt(3);
                    row.sqlText = JdbcSession.readClob(rs.getClob(4));
                    return row;
                }
            } catch (SQLException e) {
                if (log != null) {
                    log.logDbg("report cursor by child failed: " + e.getMessage());
                }
            }
        }
        return null;
    }

    private List<BindValue> loadBinds(Connection c, String sqlId, int child, int instId, int qTimeout)
            throws SQLException {
        // qTimeout 暂不透传; 与 export/genbind 同源: gv$/v$/HTZ 择优 filled
        return SqlLookup.loadBinds(c, sqlId, child, instId, new SqlLookup.WarnOut() {
            public void warn(String msg) {
                if (log != null) {
                    log.logDbg("report binds: " + msg);
                }
            }
        });
    }

    private static String nvl(String s) {
        return s == null ? "" : s;
    }

    private static boolean timedOut(long deadlineMs) {
        return System.currentTimeMillis() > deadlineMs;
    }

    private static int stmtTimeout(long deadlineMs, int overallTimeoutSec) {
        if (overallTimeoutSec <= 0) {
            return 0;
        }
        long leftMs = deadlineMs - System.currentTimeMillis();
        if (leftMs <= 0) {
            return 1;
        }
        return Math.max(1, (int) ((leftMs + 999L) / 1000L));
    }
}
