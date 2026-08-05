package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.db.HtzTables;
import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.util.NoiseFilter;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * HTZ_GV_* 增量备份 (JDBC mode B).
 * 表建在登录用户 schema 下; 失败直接抛错由 collect 退出.
 */
public class BackupService {

    private final DualLogger log;
    private final String owner;
    /** 本进程/本实例仅首次 backup 检查建表建索引 */
    private boolean ddlReady;

    public BackupService(DualLogger log, String jdbcUser) {
        this.log = log;
        this.owner = HtzTables.normalizeOwner(jdbcUser);
        this.ddlReady = false;
    }

    public static class Result {
        public List<String> newSqlIds = new ArrayList<String>();
    }

    public Result run(JdbcSession session) throws SQLException {
        Result r = new Result();
        Connection c = session.getConnection();
        Timestamp t0 = new Timestamp(System.currentTimeMillis());
        log.logStep("backup_incremental", "owner=" + owner);
        log.logDbg("backup owner=" + owner + " (login-user schema)");

        String tSql = HtzTables.qname(owner, HtzTables.GV_SQL);
        String tStat = HtzTables.qname(owner, HtzTables.GV_SQLSTATS);
        String tBind = HtzTables.qname(owner, HtzTables.GV_BIND);

        if (!ddlReady) {
            ensureTable(c, HtzTables.GV_SQL,
                    "CREATE TABLE " + tSql + " AS SELECT g.*, CAST(NULL AS DATE) AS COLLECT_TIME "
                            + "FROM GV$SQL g WHERE 1=0");
            ensureTable(c, HtzTables.GV_SQLSTATS,
                    "CREATE TABLE " + tStat + " AS SELECT g.*, CAST(NULL AS DATE) AS COLLECT_TIME "
                            + "FROM GV$SQLSTATS g WHERE 1=0");
            ensureTable(c, HtzTables.GV_BIND,
                    "CREATE TABLE " + tBind + " AS SELECT g.*, CAST(NULL AS DATE) AS COLLECT_TIME "
                            + "FROM GV$SQL_BIND_CAPTURE g WHERE 1=0");
            ensureIndexes(c, tSql, tStat, tBind);
            ddlReady = true;
            log.logDbg("backup ddl ready (tables/indexes checked once)");
        }

        int ins = HtzTables.execUpdate(c, log, "backup_insert_" + HtzTables.GV_SQL,
                "INSERT INTO " + tSql + " "
                        + "SELECT g.*, SYSDATE FROM GV$SQL g "
                        + "WHERE g.sql_id IS NOT NULL "
                        + "AND UPPER(NVL(g.parsing_schema_name, 'X')) NOT IN ('SYS', 'SYSDBA') "
                        + "AND (g.sql_fulltext IS NULL OR INSTR(g.sql_fulltext, '"
                        + NoiseFilter.PROBE_TAG + "') = 0) "
                        + "AND NOT EXISTS (SELECT 1 FROM " + tSql + " h "
                        + "WHERE h.inst_id = g.inst_id AND h.sql_id = g.sql_id "
                        + "AND h.child_number = g.child_number)");
        log.logDbg("backup INSERT " + HtzTables.GV_SQL + " rows=" + ins);

        ins = HtzTables.execUpdate(c, log, "backup_insert_" + HtzTables.GV_SQLSTATS,
                "INSERT INTO " + tStat + " "
                        + "SELECT s.*, SYSDATE FROM GV$SQLSTATS s "
                        + "WHERE s.sql_id IS NOT NULL "
                        + "AND EXISTS (SELECT 1 FROM GV$SQL g "
                        + "WHERE g.inst_id = s.inst_id AND g.sql_id = s.sql_id "
                        + "AND UPPER(NVL(g.parsing_schema_name, 'X')) NOT IN ('SYS', 'SYSDBA')) "
                        + "AND NOT EXISTS (SELECT 1 FROM " + tStat + " h "
                        + "WHERE h.inst_id = s.inst_id AND h.sql_id = s.sql_id)");
        log.logDbg("backup INSERT " + HtzTables.GV_SQLSTATS + " rows=" + ins);

        ins = HtzTables.execUpdate(c, log, "backup_insert_" + HtzTables.GV_BIND,
                "INSERT INTO " + tBind + " "
                        + "SELECT b.*, SYSDATE FROM GV$SQL_BIND_CAPTURE b "
                        + "WHERE b.sql_id IS NOT NULL "
                        + "AND EXISTS (SELECT 1 FROM GV$SQL g "
                        + "WHERE g.inst_id = b.inst_id AND g.sql_id = b.sql_id "
                        + "AND g.child_number = b.child_number "
                        + "AND UPPER(NVL(g.parsing_schema_name, 'X')) NOT IN ('SYS', 'SYSDBA')) "
                        + "AND NOT EXISTS (SELECT 1 FROM " + tBind + " h "
                        + "WHERE h.inst_id = b.inst_id AND h.sql_id = b.sql_id "
                        + "AND h.child_number = b.child_number AND h.position = b.position "
                        + "AND NVL(h.name, CHR(0)) = NVL(b.name, CHR(0)))");
        log.logDbg("backup INSERT " + HtzTables.GV_BIND + " rows=" + ins);

        c.commit();
        r.newSqlIds = fetchNewSqlIds(c, t0, tSql, tStat, tBind);
        log.logDbg("backup done BACKUP_NEW_N=" + r.newSqlIds.size());
        for (String sid : r.newSqlIds) {
            log.logDbg("backup-new sql_id=" + sid);
        }
        return r;
    }

    private void ensureTable(Connection c, String table, String ctas) throws SQLException {
        if (HtzTables.tableExists(c, owner, table)) {
            log.logDbg("backup TABLE " + HtzTables.qname(owner, table) + " exists");
            return;
        }
        log.logInfo("backup TABLE " + HtzTables.qname(owner, table) + " creating");
        HtzTables.exec(c, log, "backup_create_" + table, ctas);
        log.logInfo("backup TABLE " + HtzTables.qname(owner, table) + " created");
    }

    /**
     * 按访问路径补索引 (已存在则跳过):
     * - COLLECT_TIME: backup_new_ids 增量扫描
     * - 去重键: INSERT ... NOT EXISTS 反查
     */
    private void ensureIndexes(Connection c, String tSql, String tStat, String tBind) throws SQLException {
        // HTZ_GV_SQL: NOT EXISTS (inst_id, sql_id, child_number); new_ids on collect_time
        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_SQL_CT",
                "CREATE INDEX HTZ_GV_SQL_CT ON " + tSql + " (COLLECT_TIME)");
        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_SQL_K1",
                "CREATE INDEX HTZ_GV_SQL_K1 ON " + tSql + " (INST_ID, SQL_ID, CHILD_NUMBER)");

        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_SQLSTATS_CT",
                "CREATE INDEX HTZ_GV_SQLSTATS_CT ON " + tStat + " (COLLECT_TIME)");
        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_SQLSTATS_K1",
                "CREATE INDEX HTZ_GV_SQLSTATS_K1 ON " + tStat + " (INST_ID, SQL_ID)");

        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_BIND_CT",
                "CREATE INDEX HTZ_GV_BIND_CT ON " + tBind + " (COLLECT_TIME)");
        HtzTables.ensureIndex(c, log, owner, "HTZ_GV_BIND_K1",
                "CREATE INDEX HTZ_GV_BIND_K1 ON " + tBind
                        + " (INST_ID, SQL_ID, CHILD_NUMBER, POSITION, NAME)");
    }

    private List<String> fetchNewSqlIds(Connection c, Timestamp t0,
                                        String tSql, String tStat, String tBind) throws SQLException {
        Set<String> ids = new LinkedHashSet<String>();
        String q = "SELECT sql_id FROM ("
                + "SELECT DISTINCT sql_id FROM " + tSql + " WHERE collect_time >= ? "
                + "UNION SELECT DISTINCT sql_id FROM " + tStat + " WHERE collect_time >= ? "
                + "UNION SELECT DISTINCT sql_id FROM " + tBind + " WHERE collect_time >= ?"
                + ") ORDER BY 1";
        log.logDbg("jdbc sql [backup_new_ids]: " + q);
        PreparedStatement ps = c.prepareStatement(q);
        ps.setTimestamp(1, t0);
        ps.setTimestamp(2, t0);
        ps.setTimestamp(3, t0);
        ResultSet rs = ps.executeQuery();
        while (rs.next()) {
            String sid = rs.getString(1);
            if (sid != null && !sid.isEmpty()) {
                ids.add(sid);
            }
        }
        rs.close();
        ps.close();
        return new ArrayList<String>(ids);
    }
}
