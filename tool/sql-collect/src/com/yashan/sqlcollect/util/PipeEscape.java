package com.yashan.sqlcollect.util;

/** 管道分隔字段转义 (binds.txt / user maps) */
public final class PipeEscape {

    private PipeEscape() {}

    public static String escape(String value) {
        if (value == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder(value.length() + 8);
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\':
                    sb.append("\\\\");
                    break;
                case '|':
                    sb.append("\\|");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                default:
                    sb.append(c);
            }
        }
        return sb.toString();
    }

    public static String unescape(String value) {
        if (value == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (c == '\\' && i + 1 < value.length()) {
                char n = value.charAt(++i);
                if (n == 'n') {
                    sb.append('\n');
                } else if (n == 'r') {
                    sb.append('\r');
                } else {
                    // \\ | 及其它: 取下一字符字面值
                    sb.append(n);
                }
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    /** 最多 maxParts 段的分隔 (与 Python/Java replay 一致) */
    public static String[] split(String line, int maxParts) {
        java.util.ArrayList<String> parts = new java.util.ArrayList<String>();
        StringBuilder cur = new StringBuilder();
        boolean esc = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (esc) {
                if (c == 'n') {
                    cur.append('\n');
                } else if (c == 'r') {
                    cur.append('\r');
                } else {
                    cur.append(c);
                }
                esc = false;
                continue;
            }
            if (c == '\\') {
                esc = true;
                continue;
            }
            if (c == '|' && parts.size() < maxParts - 1) {
                parts.add(cur.toString());
                cur.setLength(0);
                continue;
            }
            cur.append(c);
        }
        if (esc) {
            cur.append('\\');
        }
        parts.add(cur.toString());
        return parts.toArray(new String[0]);
    }
}
