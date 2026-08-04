package com.yashan.sqlcollect.util;

import java.util.Locale;
import java.util.regex.Pattern;

/** SQL 噪声过滤 (与 Python sql_collect 对齐) */
public final class NoiseFilter {

    public static final String PROBE_TAG = "sql_collect_probe";
    public static final int MIN_SQL_CHARS = 20;
    public static final String[] EXCLUDE_SCHEMAS = {"SYS", "SYSDBA"};

    private static final Pattern WS = Pattern.compile("\\s+");

    private NoiseFilter() {}

    public static boolean isExcludedSchema(String schema) {
        if (schema == null || schema.isEmpty()) {
            return true;
        }
        String u = schema.trim().toUpperCase(Locale.ROOT);
        for (String ex : EXCLUDE_SCHEMAS) {
            if (ex.equals(u)) {
                return true;
            }
        }
        return false;
    }

    public static boolean isNoiseText(String sqlText) {
        if (sqlText == null) {
            return true;
        }
        String t = sqlText.trim();
        if (t.isEmpty()) {
            return true;
        }
        if (t.contains(PROBE_TAG)) {
            return true;
        }
        if (t.length() < MIN_SQL_CHARS) {
            return true;
        }
        String u = t.toUpperCase(Locale.ROOT);
        if (u.startsWith("ALTER SESSION")) {
            return true;
        }
        if (u.startsWith("SET ")) {
            return true;
        }
        String compact = WS.matcher(u).replaceAll(" ").trim();
        if ("BEGIN NULL; END;".equals(compact) || "BEGIN END;".equals(compact)
                || "BEGIN;".equals(compact) || "END;".equals(compact)) {
            return true;
        }
        if (compact.startsWith("BEGIN ") && compact.length() < 40) {
            return true;
        }
        // JDBC 拉 DBMS_OUTPUT 时自身进库的匿名块, 勿采集
        if (compact.contains("DBMS_OUTPUT.GET_LINE")
                || compact.contains("DBMS_OUTPUT.ENABLE")
                || compact.contains("DBMS_OUTPUT.PUT_LINE")) {
            // 允许业务 SQL 文本偶然包含字样? 极少; 报告脚本本身不进候选
            if (compact.contains("DBMS_OUTPUT.GET_LINE") || compact.contains("DBMS_OUTPUT.ENABLE(")) {
                return true;
            }
        }
        if (compact.contains("? := L_LINE") || compact.contains("? := L_DONE")) {
            return true;
        }
        return false;
    }
}
