package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.log.DualLogger;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * 可选 EXPLAIN 计划段 (不执行原 SQL).
 * 门控: v$sql.COMMAND_TYPE IN (1=SELECT, 6=WITH CTE); 字典见 v$sqlcommand.
 */
public final class ExplainPlanSection {

    /** SELECT */
    public static final int CMD_SELECT = 1;
    /** WITH CTE */
    public static final int CMD_WITH_CTE = 6;

    private ExplainPlanSection() {
    }

    public static boolean isQueryCommand(int commandType) {
        return commandType == CMD_SELECT || commandType == CMD_WITH_CTE;
    }

    /**
     * 追加 EXPLAIN 段到报告.
     * @return true=已输出 EXPLAIN 正文; false=跳过或失败(仍可能写了说明行)
     */
    public static boolean append(Connection c, String sqlId, String sqlText, StringBuilder out,
                                 DualLogger log, int queryTimeoutSec) {
        out.append('\n');
        out.append("****************************************************************************************\n");
        out.append("EXPLAIN PLAN (optional; Id = position; does NOT execute original SQL)\n");
        out.append("****************************************************************************************\n");

        CmdInfo cmd = loadCommandType(c, sqlId, log);
        if (cmd == null || cmd.commandType == null) {
            out.append("[SKIP] explain: cannot read COMMAND_TYPE for sql_id=")
                    .append(sqlId == null ? "" : sqlId).append('\n');
            if (log != null) {
                log.logInfo("explain skip sql_id=" + sqlId + " reason=no_command_type");
            }
            return false;
        }
        out.append("command_type=").append(cmd.commandType)
                .append(" command_name=").append(cmd.commandName == null ? "?" : cmd.commandName)
                .append('\n');

        if (!isQueryCommand(cmd.commandType.intValue())) {
            out.append("[SKIP] explain: non-query (only SELECT/WITH CTE); flag ignored\n");
            if (log != null) {
                log.logInfo("explain skip sql_id=" + sqlId
                        + " command_type=" + cmd.commandType
                        + " name=" + cmd.commandName);
            }
            return false;
        }

        if (sqlText == null || sqlText.trim().isEmpty()) {
            out.append("[SKIP] explain: empty sql_text\n");
            return false;
        }

        String cleaned = stripTrailingTerminators(sqlText);
        String explSql = "EXPLAIN PLAN FOR " + cleaned;
        if (log != null) {
            log.logDbg("explain sql_id=" + sqlId + " chars=" + cleaned.length());
        }

        try (Statement st = c.createStatement()) {
            if (queryTimeoutSec > 0) {
                st.setQueryTimeout(queryTimeoutSec);
            }
            try (ResultSet rs = st.executeQuery(explSql)) {
                int lines = 0;
                while (rs.next()) {
                    String line = rs.getString(1);
                    out.append(line == null ? "" : line).append('\n');
                    lines++;
                }
                if (lines == 0) {
                    out.append("(explain returned 0 rows)\n");
                }
                if (log != null) {
                    log.logInfo("explain ok sql_id=" + sqlId + " lines=" + lines
                            + " command_type=" + cmd.commandType);
                }
                return lines > 0;
            }
        } catch (SQLException e) {
            out.append("[ERROR] explain: ").append(e.getMessage()).append('\n');
            if (log != null) {
                log.logWarn("explain failed sql_id=" + sqlId + ": " + e.getMessage());
            }
            return false;
        }
    }

    static String stripTrailingTerminators(String sql) {
        String s = sql.trim();
        while (s.endsWith(";") || s.endsWith("/")) {
            s = s.substring(0, s.length() - 1).trim();
        }
        return s;
    }

    private static final class CmdInfo {
        Integer commandType;
        String commandName;
    }

    private static CmdInfo loadCommandType(Connection c, String sqlId, DualLogger log) {
        String[] qs = new String[] {
            "SELECT command_type FROM ("
                    + " SELECT command_type FROM gv$sql WHERE sql_id = ?"
                    + " ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST"
                    + ") WHERE ROWNUM = 1",
            "SELECT command_type FROM ("
                    + " SELECT command_type FROM v$sql WHERE sql_id = ?"
                    + " ORDER BY last_active_time DESC NULLS LAST, executions DESC NULLS LAST"
                    + ") WHERE ROWNUM = 1"
        };
        Integer ct = null;
        for (String q : qs) {
            try (PreparedStatement ps = c.prepareStatement(q)) {
                ps.setQueryTimeout(30);
                ps.setString(1, sqlId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        int v = rs.getInt(1);
                        if (!rs.wasNull()) {
                            ct = Integer.valueOf(v);
                            break;
                        }
                    }
                }
            } catch (SQLException e) {
                if (log != null) {
                    log.logDbg("explain command_type query failed: " + e.getMessage());
                }
            }
        }
        if (ct == null) {
            return null;
        }
        CmdInfo info = new CmdInfo();
        info.commandType = ct;
        info.commandName = lookupCommandName(c, ct.intValue(), log);
        return info;
    }

    private static String lookupCommandName(Connection c, int commandType, DualLogger log) {
        String[] qs = new String[] {
            "SELECT command_name FROM v$sqlcommand WHERE command_type = ?",
            "SELECT command_name FROM gv$sqlcommand WHERE command_type = ? AND ROWNUM = 1"
        };
        for (String q : qs) {
            try (PreparedStatement ps = c.prepareStatement(q)) {
                ps.setQueryTimeout(15);
                ps.setInt(1, commandType);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getString(1);
                    }
                }
            } catch (SQLException e) {
                if (log != null) {
                    log.logDbg("explain command_name lookup failed: " + e.getMessage());
                }
            }
        }
        return null;
    }
}
