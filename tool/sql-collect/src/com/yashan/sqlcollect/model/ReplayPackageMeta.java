package com.yashan.sqlcollect.model;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

/** replay 包 meta.txt 字段; 含 SQL 文本指纹 (供 SQL Map 一致性硬校验) */
public class ReplayPackageMeta {
    /** meta.txt / HTZ 列名: UTF-8 SHA-256 小写 hex */
    public static final String META_SQL_SHA256 = "sql_sha256";

    public String sqlId = "";
    public int childNumber;
    public int instId = 1;
    public long hashValue;
    public String parsingSchema = "";
    public int sqlLen;
    public String sqlSha256 = "";

    /** 对 SQL 文本做 UTF-8 SHA-256, 返回 64 位小写 hex; null 视为空串 */
    public static String sha256Utf8(String sql) {
        byte[] raw = (sql == null ? "" : sql).getBytes(StandardCharsets.UTF_8);
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] dig = md.digest(raw);
            StringBuilder sb = new StringBuilder(dig.length * 2);
            for (int i = 0; i < dig.length; i++) {
                sb.append(String.format("%02x", Integer.valueOf(dig[i] & 0xff)));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }

    /**
     * 硬校验: expected 非空时必须与 sql 指纹一致 (忽略大小写).
     * expected 为空则视为 legacy 包, 不校验.
     *
     * @return null 表示通过; 非 null 为失败原因英文短句
     */
    public static String mismatchReason(String sql, String expectedSha) {
        String actual = sha256Utf8(sql);
        if (expectedSha == null) {
            return null;
        }
        String exp = expectedSha.trim();
        if (exp.isEmpty()) {
            return null;
        }
        if (exp.equalsIgnoreCase(actual)) {
            return null;
        }
        return "sql_sha256 mismatch expected=" + exp + " actual=" + actual;
    }
}
