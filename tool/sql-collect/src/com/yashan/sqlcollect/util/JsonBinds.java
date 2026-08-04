package com.yashan.sqlcollect.util;

import com.yashan.sqlcollect.model.BindValue;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** binds.json 最小读写 (position,name,datatype,value,was_captured) */
public final class JsonBinds {

    private JsonBinds() {}

    public static String write(List<BindValue> binds) {
        StringBuilder sb = new StringBuilder();
        sb.append("[");
        for (int i = 0; i < binds.size(); i++) {
            if (i > 0) {
                sb.append(",");
            }
            BindValue b = binds.get(i);
            sb.append("{");
            sb.append("\"position\":").append(b.position);
            sb.append(",\"name\":").append(jsonStr(b.name));
            sb.append(",\"datatype\":").append(jsonStr(b.datatype));
            sb.append(",\"value\":").append(jsonStr(b.value));
            sb.append(",\"was_captured\":").append(jsonStr(b.wasCaptured));
            sb.append("}");
        }
        sb.append("]");
        return sb.toString();
    }

    public static List<BindValue> read(String json) {
        List<BindValue> out = new ArrayList<BindValue>();
        if (json == null || json.trim().isEmpty() || "[]".equals(json.trim())) {
            return out;
        }
        // 字符串感知的花括号深度扫描: 值含 { } 时正则 \{([^{}]*)\} 会静默丢绑定
        int depth = 0;
        boolean inStr = false;
        int start = -1;
        for (int i = 0; i < json.length(); i++) {
            char c = json.charAt(i);
            if (inStr) {
                if (c == '\\') {
                    i++;
                    continue;
                }
                if (c == '"') {
                    inStr = false;
                }
                continue;
            }
            if (c == '"') {
                inStr = true;
                continue;
            }
            if (c == '{') {
                if (depth == 0) {
                    start = i;
                }
                depth++;
            } else if (c == '}') {
                if (depth > 0) {
                    depth--;
                    if (depth == 0 && start >= 0) {
                        parseObject(json.substring(start, i + 1), out);
                        start = -1;
                    }
                }
            }
        }
        return out;
    }

    private static void parseObject(String obj, List<BindValue> out) {
        String pos = jsonField(obj, "position");
        if (pos == null || pos.isEmpty()) {
            return;
        }
        BindValue b = new BindValue();
        try {
            b.position = Integer.parseInt(pos.trim());
        } catch (NumberFormatException e) {
            return;
        }
        b.name = jsonField(obj, "name");
        b.datatype = jsonField(obj, "datatype");
        b.value = jsonField(obj, "value");
        b.wasCaptured = jsonField(obj, "was_captured");
        if (b.datatype == null) {
            b.datatype = "";
        }
        if (b.value == null) {
            b.value = "";
        }
        if (b.wasCaptured == null) {
            b.wasCaptured = "";
        }
        out.add(b);
    }

    /** 供 ReplayEngine 使用的 position|datatype|value 三元组 */
    public static List<String[]> toReplayRows(List<BindValue> binds) {
        List<String[]> rows = new ArrayList<String[]>();
        for (BindValue b : binds) {
            rows.add(new String[] {
                String.valueOf(b.position),
                b.datatype == null ? "" : b.datatype,
                b.value == null ? "" : b.value
            });
        }
        return rows;
    }

    static String jsonStr(String s) {
        if (s == null) {
            return "null";
        }
        StringBuilder sb = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '\\':
                    sb.append("\\\\");
                    break;
                case '"':
                    sb.append("\\\"");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                default:
                    if (c < 32) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        sb.append("\"");
        return sb.toString();
    }

    static String jsonUnescape(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\\' && i + 1 < s.length()) {
                char n = s.charAt(++i);
                if (n == 'n') {
                    sb.append('\n');
                } else if (n == 'r') {
                    sb.append('\r');
                } else if (n == 't') {
                    sb.append('\t');
                } else if (n == 'b') {
                    sb.append('\b');
                } else if (n == 'f') {
                    sb.append('\f');
                } else if (n == 'u' && i + 4 < s.length()) {
                    String hex = s.substring(i + 1, i + 5);
                    try {
                        sb.append((char) Integer.parseInt(hex, 16));
                        i += 4;
                    } catch (NumberFormatException e) {
                        // 非法 \\uXXXX: 保留字面 u 与后续字符
                        sb.append('u');
                    }
                } else {
                    sb.append(n);
                }
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    private static String jsonField(String obj, String key) {
        Pattern pStr = Pattern.compile(
                "\\\"" + key + "\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\"");
        Matcher m = pStr.matcher(obj);
        if (m.find()) {
            return jsonUnescape(m.group(1));
        }
        Pattern pNum = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*(-?\\d+)");
        m = pNum.matcher(obj);
        if (m.find()) {
            return m.group(1);
        }
        Pattern pNull = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*null");
        if (pNull.matcher(obj).find()) {
            return null;
        }
        return "";
    }
}
