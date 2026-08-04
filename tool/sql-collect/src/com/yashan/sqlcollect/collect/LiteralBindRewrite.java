package com.yashan.sqlcollect.collect;

import com.yashan.sqlcollect.model.BindValue;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * LITERAL SQL 绑字面量改写 (纯 Java, 无 VARCHAR2 上限).
 * 对齐 sql.sql 语义: 优先按 :name 替换; 否则按 ? 顺序替换.
 */
public final class LiteralBindRewrite {

    /** 单 bind 字面量最大字符数; 超出截断并标注 */
    public static final int MAX_LITERAL_CHARS = 8000;

    private LiteralBindRewrite() {}

    public static String rewrite(String sql, List<BindValue> binds) {
        if (sql == null) {
            return "";
        }
        if (binds == null || binds.isEmpty()) {
            return sql;
        }
        String text = sql;
        boolean useQuestion = usesQuestionBind(text);
        List<String> warnings = new ArrayList<String>();
        for (BindValue b : binds) {
            if (b == null) {
                continue;
            }
            String repl = toLiteral(b, warnings);
            String pattern = bindPattern(b.name);
            if (!useQuestion && pattern != null) {
                String next = replaceFirstOutsideQuotes(text, pattern, repl);
                if (!next.equals(text)) {
                    text = next;
                    continue;
                }
            }
            int q = indexOfQuestionOutsideQuotes(text);
            if (q < 0) {
                warnings.add("no placeholder for bind pos=" + b.position + " name=" + b.name);
                continue;
            }
            text = text.substring(0, q) + repl + text.substring(q + 1);
        }
        if (!warnings.isEmpty()) {
            StringBuilder sb = new StringBuilder(text);
            sb.append("\n-- LITERAL WARN: ");
            for (int i = 0; i < warnings.size(); i++) {
                if (i > 0) {
                    sb.append("; ");
                }
                sb.append(warnings.get(i));
            }
            return sb.toString();
        }
        return text;
    }

    static String toLiteral(BindValue b, List<String> warnings) {
        String raw = b.value;
        if (raw == null || raw.isEmpty() || "\\N".equals(raw)) {
            return "NULL";
        }
        String dt = b.datatype == null ? "" : b.datatype.toUpperCase(Locale.ROOT);
        String v = raw;
        boolean truncated = false;
        if (v.length() > MAX_LITERAL_CHARS) {
            v = v.substring(0, MAX_LITERAL_CHARS);
            truncated = true;
            warnings.add("truncated value pos=" + b.position + " to " + MAX_LITERAL_CHARS + " chars");
        }
        String lit;
        if (dt.contains("NUMBER") || dt.contains("DECIMAL") || dt.contains("INT")
                || dt.contains("FLOAT") || dt.contains("DOUBLE") || dt.contains("BINARY_")) {
            lit = v.trim();
        } else if (dt.contains("DATE") && !dt.contains("TIMESTAMP")) {
            lit = "to_date('" + escapeQuote(v) + "')";
        } else if (dt.contains("TIMESTAMP") || dt.contains("TIME")) {
            lit = "to_timestamp('" + escapeQuote(v) + "')";
        } else {
            lit = "'" + escapeQuote(v) + "'";
        }
        if (truncated) {
            lit = lit + " /*truncated*/";
        }
        return lit;
    }

    static String bindPattern(String name) {
        if (name == null || name.trim().isEmpty()) {
            return null;
        }
        String n = name.trim();
        if (n.regionMatches(true, 0, ":SYS_B_", 0, 7)) {
            return ":\"" + n.substring(1) + "\"";
        }
        if (n.startsWith(":")) {
            return n;
        }
        return ":" + n.replaceFirst("^:+", "");
    }

    static boolean usesQuestionBind(String text) {
        return indexOfQuestionOutsideQuotes(text) >= 0;
    }

    static int indexOfQuestionOutsideQuotes(String text) {
        boolean inStr = false;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '\'') {
                if (inStr && i + 1 < text.length() && text.charAt(i + 1) == '\'') {
                    i++;
                } else {
                    inStr = !inStr;
                }
            } else if (!inStr && c == '?') {
                return i;
            }
        }
        return -1;
    }

    static String replaceFirstOutsideQuotes(String text, String pattern, String replacement) {
        if (pattern == null || pattern.isEmpty()) {
            return text;
        }
        boolean inStr = false;
        int plen = pattern.length();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '\'') {
                if (inStr && i + 1 < text.length() && text.charAt(i + 1) == '\'') {
                    i++;
                } else {
                    inStr = !inStr;
                }
                continue;
            }
            if (inStr) {
                continue;
            }
            if (i + plen <= text.length()
                    && text.regionMatches(true, i, pattern, 0, plen)) {
                char next = i + plen < text.length() ? text.charAt(i + plen) : 0;
                if (pattern.startsWith(":") && next >= '0' && next <= '9') {
                    continue;
                }
                return text.substring(0, i) + replacement + text.substring(i + plen);
            }
        }
        return text;
    }

    private static String escapeQuote(String s) {
        return s.replace("'", "''");
    }
}
