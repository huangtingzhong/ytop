package com.yashan.sqlcollect.util;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** 简单 INI 解析器, 支持 # 注释, 不做 % 插值 */
public final class IniUtil {

    private IniUtil() {}

    public static Map<String, Map<String, String>> load(Path path) throws IOException {
        String raw = new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
        return parse(raw);
    }

    public static Map<String, Map<String, String>> parse(String raw) throws IOException {
        Map<String, Map<String, String>> sections = new LinkedHashMap<String, Map<String, String>>();
        String current = null;
        BufferedReader br = new BufferedReader(new StringReader(raw));
        String line;
        while ((line = br.readLine()) != null) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith(";")) {
                continue;
            }
            if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
                current = trimmed.substring(1, trimmed.length() - 1).trim();
                if (!sections.containsKey(current)) {
                    sections.put(current, new LinkedHashMap<String, String>());
                }
                continue;
            }
            if (current == null) {
                current = "jdbc";
                if (!sections.containsKey(current)) {
                    sections.put(current, new LinkedHashMap<String, String>());
                }
            }
            int eq = trimmed.indexOf('=');
            if (eq <= 0) {
                continue;
            }
            String key = trimmed.substring(0, eq).trim().toLowerCase(Locale.ROOT);
            String val = trimmed.substring(eq + 1).trim();
            sections.get(current).put(key, val);
        }
        return sections;
    }

    public static boolean truthy(String value) {
        if (value == null || value.isEmpty()) {
            return false;
        }
        String s = value.trim().toLowerCase(Locale.ROOT);
        return "1".equals(s) || "true".equals(s) || "yes".equals(s) || "on".equals(s)
                || "alter".equals(s) || "alter-session".equals(s) || "alter_session".equals(s);
    }
}
