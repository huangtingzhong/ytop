package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.db.JdbcSession;
import com.yashan.sqlcollect.log.DualLogger;
import com.yashan.sqlcollect.model.SqlCandidate;
import com.yashan.sqlcollect.util.NoiseFilter;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 从 gv$/v$sql 列出候选 sql_id.
 * 每一轮: 先按活跃会话 (GV$SESSION, 执行时间长优先) 排前面, 再接其余候选.
 */
public class CandidateService {

    private final DualLogger log;

    public CandidateService(DualLogger log) {
        this.log = log;
    }

    public List<SqlCandidate> list(JdbcSession session) {
        Connection c = session.getConnection();
        List<String> activeIds = listActiveSqlIds(c);
        List<SqlCandidate> fromGv = queryAll(c, true);
        List<SqlCandidate> pool = fromGv;
        if (pool.isEmpty()) {
            log.logWarn("gv$sql list failed or empty; try v$sql");
            pool = queryAll(c, false);
        }
        List<SqlCandidate> ordered = prioritizeActive(c, pool, activeIds);
        log.logInfo("candidates=" + ordered.size()
                + " active_session_sql=" + activeIds.size()
                + " active_first=" + countActiveFirst(ordered, activeIds));
        return ordered;
    }

    /** 活跃会话中的 sql_id, 按 exec_start_time 升序 (跑得最久的优先). */
    private List<String> listActiveSqlIds(Connection c) {
        LinkedHashSet<String> ids = new LinkedHashSet<String>();
        // 与 ytop CollectSessionDetails 过滤对齐; 无 SQL_CHILD_NUMBER (Yashan 无此列)
        String[] sqls = new String[] {
            "SELECT s.sql_id FROM gv$session s "
                    + "WHERE s.TYPE NOT IN ('BACKGROUND') "
                    + "AND NVL(NULLIF(TRIM(s.status), ''), 'ACTIVE') NOT IN ('INACTIVE') "
                    + "AND s.sql_id IS NOT NULL "
                    + "AND LENGTH(TRIM(s.sql_id)) >= 5 "
                    + "AND NOT (s.INST_ID = TO_NUMBER(SYS_CONTEXT('USERENV', 'INSTANCE')) "
                    + "AND s.SID = TO_NUMBER(SYS_CONTEXT('USERENV', 'SID'))) "
                    + "ORDER BY s.exec_start_time ASC NULLS LAST, s.sql_id",
            "SELECT s.sql_id FROM v$session s "
                    + "WHERE s.TYPE NOT IN ('BACKGROUND') "
                    + "AND NVL(NULLIF(TRIM(s.status), ''), 'ACTIVE') NOT IN ('INACTIVE') "
                    + "AND s.sql_id IS NOT NULL "
                    + "AND LENGTH(TRIM(s.sql_id)) >= 5 "
                    + "AND s.SID <> TO_NUMBER(SYS_CONTEXT('USERENV', 'SID')) "
                    + "ORDER BY s.exec_start_time ASC NULLS LAST, s.sql_id"
        };
        for (int i = 0; i < sqls.length; i++) {
            try (PreparedStatement ps = c.prepareStatement(sqls[i]);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String id = rs.getString(1);
                    if (id != null) {
                        id = id.trim();
                        if (id.length() >= 5) {
                            ids.add(id);
                        }
                    }
                }
                if (!ids.isEmpty()) {
                    if (log != null) {
                        log.logDbg("active session sql_ids=" + ids.size()
                                + " source=" + (i == 0 ? "gv$session" : "v$session"));
                    }
                    return new ArrayList<String>(ids);
                }
            } catch (SQLException e) {
                if (log != null) {
                    log.logDbg("active session query failed: " + e.getMessage());
                }
            }
        }
        return new ArrayList<String>();
    }

    private List<SqlCandidate> queryAll(Connection c, boolean useGv) {
        String view = useGv ? "gv$sql" : "v$sql";
        String sql = "SELECT sql_id, MAX(parsing_schema_name) AS parsing_schema_name, "
                + "MAX(DBMS_LOB.GETLENGTH(sql_fulltext)) AS sql_len, "
                + "MAX(DBMS_LOB.SUBSTR(sql_fulltext, 180, 1)) AS snip "
                + "FROM " + view + " "
                + "WHERE parsing_schema_name IS NOT NULL "
                + "AND UPPER(parsing_schema_name) NOT IN ('SYS','SYSDBA') "
                + "AND sql_id IS NOT NULL "
                + "AND sql_fulltext NOT LIKE '%" + NoiseFilter.PROBE_TAG + "%' "
                + "GROUP BY sql_id "
                + "ORDER BY sql_id";
        List<SqlCandidate> out = new ArrayList<SqlCandidate>();
        try (PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                SqlCandidate cand = toCandidate(rs.getString(1), rs.getString(2),
                        rs.getInt(3), rs.getString(4));
                if (cand != null) {
                    out.add(cand);
                }
            }
        } catch (SQLException e) {
            log.logDbg("candidate query " + view + " failed: " + e.getMessage());
            return new ArrayList<SqlCandidate>();
        }
        return out;
    }

    /**
     * 活跃 sql_id 置顶; 若活跃但不在全量池中, 再按 sql_id 从 gv$/v$sql 补一条
     * (避免热点 SQL 因全量列表截断/瞬时漏扫而排不到前面).
     */
    private List<SqlCandidate> prioritizeActive(Connection c, List<SqlCandidate> pool,
                                                List<String> activeIds) {
        if (activeIds == null || activeIds.isEmpty()) {
            return pool;
        }
        Map<String, SqlCandidate> byId = new LinkedHashMap<String, SqlCandidate>();
        for (SqlCandidate cand : pool) {
            if (cand != null && cand.sqlId != null) {
                byId.put(cand.sqlId, cand);
            }
        }
        List<SqlCandidate> out = new ArrayList<SqlCandidate>();
        Set<String> seen = new LinkedHashSet<String>();
        for (String id : activeIds) {
            if (id == null || seen.contains(id)) {
                continue;
            }
            SqlCandidate cand = byId.get(id);
            if (cand == null) {
                cand = lookupOne(c, id);
            }
            if (cand == null) {
                continue;
            }
            out.add(cand);
            seen.add(id);
        }
        for (SqlCandidate cand : pool) {
            if (cand == null || cand.sqlId == null || seen.contains(cand.sqlId)) {
                continue;
            }
            out.add(cand);
            seen.add(cand.sqlId);
        }
        return out;
    }

    private SqlCandidate lookupOne(Connection c, String sqlId) {
        String[] sqls = new String[] {
            "SELECT sql_id, MAX(parsing_schema_name), "
                    + "MAX(DBMS_LOB.GETLENGTH(sql_fulltext)), "
                    + "MAX(DBMS_LOB.SUBSTR(sql_fulltext, 180, 1)) "
                    + "FROM gv$sql WHERE sql_id = ? "
                    + "AND parsing_schema_name IS NOT NULL "
                    + "AND UPPER(parsing_schema_name) NOT IN ('SYS','SYSDBA') "
                    + "AND (sql_fulltext IS NULL OR sql_fulltext NOT LIKE '%"
                    + NoiseFilter.PROBE_TAG + "%') "
                    + "GROUP BY sql_id",
            "SELECT sql_id, MAX(parsing_schema_name), "
                    + "MAX(DBMS_LOB.GETLENGTH(sql_fulltext)), "
                    + "MAX(DBMS_LOB.SUBSTR(sql_fulltext, 180, 1)) "
                    + "FROM v$sql WHERE sql_id = ? "
                    + "AND parsing_schema_name IS NOT NULL "
                    + "AND UPPER(parsing_schema_name) NOT IN ('SYS','SYSDBA') "
                    + "AND (sql_fulltext IS NULL OR sql_fulltext NOT LIKE '%"
                    + NoiseFilter.PROBE_TAG + "%') "
                    + "GROUP BY sql_id"
        };
        for (String sql : sqls) {
            try (PreparedStatement ps = c.prepareStatement(sql)) {
                ps.setString(1, sqlId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        SqlCandidate cand = toCandidate(rs.getString(1), rs.getString(2),
                                rs.getInt(3), rs.getString(4));
                        if (cand != null) {
                            log.logDbg("active sql_id not in pool; added " + sqlId
                                    + " schema=" + cand.schema);
                            return cand;
                        }
                    }
                }
            } catch (SQLException e) {
                log.logDbg("lookup active sql_id=" + sqlId + ": " + e.getMessage());
            }
        }
        return null;
    }

    private static SqlCandidate toCandidate(String sqlId, String schema, int sqlLen, String snip) {
        if (sqlId == null || sqlId.length() < 5) {
            return null;
        }
        if (NoiseFilter.isExcludedSchema(schema)) {
            return null;
        }
        if (sqlLen < NoiseFilter.MIN_SQL_CHARS) {
            return null;
        }
        if (NoiseFilter.isNoiseText(snip)) {
            return null;
        }
        return new SqlCandidate(sqlId, schema, sqlLen, snip);
    }

    private static int countActiveFirst(List<SqlCandidate> ordered, List<String> activeIds) {
        if (ordered == null || activeIds == null || activeIds.isEmpty()) {
            return 0;
        }
        Set<String> active = new LinkedHashSet<String>();
        for (String id : activeIds) {
            if (id != null) {
                active.add(id);
            }
        }
        int n = 0;
        for (SqlCandidate cand : ordered) {
            if (cand == null || cand.sqlId == null || !active.contains(cand.sqlId)) {
                break;
            }
            n++;
        }
        return n;
    }
}
