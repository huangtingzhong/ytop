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
import java.util.List;

/** 从 gv$/v$sql 列出候选 sql_id */
public class CandidateService {

    private final DualLogger log;

    public CandidateService(DualLogger log) {
        this.log = log;
    }

    public List<SqlCandidate> list(JdbcSession session) {
        List<SqlCandidate> fromGv = query(session.getConnection(), true);
        if (!fromGv.isEmpty()) {
            return fromGv;
        }
        log.logWarn("gv$sql list failed or empty; try v$sql");
        return query(session.getConnection(), false);
    }

    private List<SqlCandidate> query(Connection c, boolean useGv) {
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
                String sqlId = rs.getString(1);
                String schema = rs.getString(2);
                int sqlLen = rs.getInt(3);
                String snip = rs.getString(4);
                if (sqlId == null || sqlId.length() < 5) {
                    continue;
                }
                if (NoiseFilter.isExcludedSchema(schema)) {
                    continue;
                }
                if (sqlLen < NoiseFilter.MIN_SQL_CHARS) {
                    continue;
                }
                if (NoiseFilter.isNoiseText(snip)) {
                    continue;
                }
                out.add(new SqlCandidate(sqlId, schema, sqlLen, snip));
            }
        } catch (SQLException e) {
            log.logDbg("candidate query " + view + " failed: " + e.getMessage());
            return new ArrayList<SqlCandidate>();
        }
        return out;
    }
}
