package com.yashan.sqlcollect.model;

/** gv$/v$sql 候选 SQL 行 */
public class SqlCandidate {
    public String sqlId;
    public String schema;
    public int sqlLen;
    public String snippet;

    public SqlCandidate(String sqlId, String schema, int sqlLen, String snippet) {
        this.sqlId = sqlId;
        this.schema = schema;
        this.sqlLen = sqlLen;
        this.snippet = snippet == null ? "" : snippet;
    }
}
