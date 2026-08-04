package com.yashan.sqlcollect.config;

import com.yashan.sqlcollect.util.IniUtil;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** 加载/写入 jdbc_replay.ini */
public class JdbcConfig {

    public static final String DEFAULT_CONFIG = "./jdbc_replay.ini";

    public static final String TEMPLATE =
            "# sql-collect JDBC config\n"
            + "# Default: ./jdbc_replay.ini\n\n"
            + "[jdbc]\n"
            + "jdbc_jar = /path/to/yashandb-jdbc.jar\n"
            + "jdbc_url = jdbc:yasdb://127.0.0.1:11688/yasdb\n"
            + "user = htz\n"
            + "password = htz123\n"
            + "schema_via_alter = false\n"
            + "# current_schema = HNCB\n\n"
            + "# [map.HNCB]\n"
            + "# user = hncb\n"
            + "# password = hncb123\n";

    public String configPath;
    public String jdbcJar;
    public String jdbcUrl;
    public String user;
    public String password;
    public boolean schemaViaAlter;
    public String currentSchema = "";
    /** schema -> [user, password] */
    public Map<String, String[]> maps = new HashMap<String, String[]>();

    public static Path resolvePath(String path) {
        String raw = path == null || path.isEmpty() ? DEFAULT_CONFIG : path;
        return Paths.get(raw).toAbsolutePath().normalize();
    }

    public static JdbcConfig load(String path) throws IOException {
        Path p = resolvePath(path);
        if (!Files.isRegularFile(p)) {
            throw new IOException("jdbc config not found: " + p
                    + "\n  generate: sql-collect replay --init-config");
        }
        String content = new String(Files.readAllBytes(p), StandardCharsets.UTF_8).trim();
        if (content.isEmpty()) {
            throw new IOException("jdbc config empty: " + p);
        }
        Map<String, Map<String, String>> sections = IniUtil.parse(content);
        String jdbcSection = "jdbc";
        if (!sections.containsKey(jdbcSection)) {
            for (String sec : sections.keySet()) {
                if (!sec.toLowerCase(Locale.ROOT).startsWith("map.")) {
                    jdbcSection = sec;
                    break;
                }
            }
        }
        Map<String, String> j = sections.get(jdbcSection);
        if (j == null || j.isEmpty()) {
            throw new IOException("jdbc config has no [jdbc] section: " + p);
        }
        JdbcConfig cfg = new JdbcConfig();
        cfg.configPath = p.toString();
        cfg.jdbcJar = first(j, "jdbc_jar", "jar");
        cfg.jdbcUrl = first(j, "jdbc_url", "url");
        cfg.user = first(j, "user", "username");
        cfg.password = first(j, "password", "passwd");
        if (cfg.password == null) {
            cfg.password = "";
        }
        cfg.schemaViaAlter = IniUtil.truthy(j.get("schema_via_alter"));
        if (j.containsKey("login_mode_alter")) {
            cfg.schemaViaAlter = cfg.schemaViaAlter || IniUtil.truthy(j.get("login_mode_alter"));
        }
        cfg.currentSchema = j.containsKey("current_schema") ? j.get("current_schema").trim() : "";
        if (cfg.jdbcUrl == null || cfg.jdbcUrl.isEmpty()) {
            throw new IOException("jdbc config needs jdbc_url");
        }
        if (cfg.jdbcJar == null || cfg.jdbcJar.isEmpty()) {
            throw new IOException("jdbc config needs jdbc_jar");
        }
        if (!Files.isRegularFile(Paths.get(cfg.jdbcJar))) {
            throw new IOException("jdbc_jar not found: " + cfg.jdbcJar);
        }
        if (cfg.user == null || cfg.user.isEmpty()) {
            throw new IOException("jdbc config needs user");
        }
        for (Map.Entry<String, Map<String, String>> e : sections.entrySet()) {
            if (!e.getKey().toLowerCase(Locale.ROOT).startsWith("map.")) {
                continue;
            }
            String schema = e.getKey().substring(4).trim().toUpperCase(Locale.ROOT);
            if (schema.isEmpty()) {
                continue;
            }
            Map<String, String> m = e.getValue();
            String mu = first(m, "user", "username");
            if (mu == null || mu.isEmpty()) {
                mu = schema;
            }
            String mp = first(m, "password", "passwd");
            if (mp == null) {
                mp = cfg.password;
            }
            cfg.maps.put(schema, new String[] {mu, mp});
        }
        return cfg;
    }

    public static String writeTemplate(String path, boolean overwrite) throws IOException {
        Path p = resolvePath(path);
        if (Files.exists(p) && !overwrite) {
            throw new IOException("jdbc config already exists: " + p + " (pass --overwrite)");
        }
        Path parent = p.getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Files.write(p, TEMPLATE.getBytes(StandardCharsets.UTF_8));
        return p.toString();
    }

    private static String first(Map<String, String> m, String... keys) {
        for (String k : keys) {
            if (m.containsKey(k)) {
                String v = m.get(k);
                if (v != null) {
                    return v.trim();
                }
            }
        }
        return null;
    }
}
