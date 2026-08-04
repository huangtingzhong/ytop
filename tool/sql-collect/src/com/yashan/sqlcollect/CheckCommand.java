package com.yashan.sqlcollect;

import com.yashan.sqlcollect.cli.Args;
import com.yashan.sqlcollect.config.JdbcConfig;
import com.yashan.sqlcollect.db.HtzTables;
import com.yashan.sqlcollect.db.JdbcPool;
import com.yashan.sqlcollect.log.DualLogger;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Map;

/**
 * 长任务前健康检查: 配置/驱动/连通/GV$ 权限/建表探测/[map.*] 登录.
 */
public class CheckCommand {

    public static final String DEFAULT_LOG_DIR = "logs";

    public int run(Args args) {
        DualLogger log = null;
        try {
            Path logDir = Paths.get(args.opt("log-dir", DEFAULT_LOG_DIR));
            boolean debug = args.resolveDebug();
            log = new DualLogger(logDir, "check", debug);
            log.logInfo("debug=" + debug);
            return runBody(args, log);
        } catch (IOException e) {
            System.err.println("[ERROR] log init failed: " + e.getMessage());
            return 2;
        } finally {
            if (log != null) {
                log.close();
            }
        }
    }

    private int runBody(Args args, DualLogger log) {
        String cfgPath = args.opt("jdbc-config", JdbcConfig.DEFAULT_CONFIG);
        log.logInfo("sql-collect v" + Version.VERSION + " check");
        log.logInfo("jdbc_config=" + cfgPath);

        JdbcConfig cfg;
        try {
            cfg = JdbcConfig.load(cfgPath);
        } catch (IOException e) {
            log.logError("config: FAIL " + e.getMessage());
            return 1;
        }
        log.logInfo("config: OK jar=" + cfg.jdbcJar + " url=" + cfg.jdbcUrl + " user=" + cfg.user);

        try {
            Class.forName("com.yashandb.jdbc.Driver");
            log.logInfo("driver: OK com.yashandb.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            log.logError("driver: FAIL " + e.getMessage());
            return 1;
        }

        JdbcPool pool = new JdbcPool(log, 1);
        int fail = 0;
        try {
            Connection c;
            try {
                c = pool.borrow(cfg.jdbcUrl, cfg.user, cfg.password);
            } catch (SQLException e) {
                log.logError("connect jdbc user: FAIL " + e.getMessage());
                return 1;
            }
            try {
                if (!probeSelect(c, "SELECT 1 FROM dual", log, "dual")) {
                    fail++;
                }
                if (!probeSelect(c, "SELECT COUNT(*) FROM gv$sql WHERE ROWNUM = 1", log, "GV$SQL")) {
                    fail++;
                }
                if (!probeSelect(c,
                        "SELECT COUNT(*) FROM gv$sql_bind_capture WHERE ROWNUM = 1",
                        log, "GV$SQL_BIND_CAPTURE")) {
                    fail++;
                }
                if (!probeCreateDrop(c, log)) {
                    fail++;
                }
            } finally {
                try {
                    c.close();
                } catch (SQLException ignored) {
                }
            }

            for (Map.Entry<String, String[]> e : cfg.maps.entrySet()) {
                String schema = e.getKey();
                String[] cred = e.getValue();
                try {
                    Connection mc = pool.borrow(cfg.jdbcUrl, cred[0], cred[1]);
                    try {
                        if (probeSelect(mc, "SELECT 1 FROM dual", log, "map." + schema + " user=" + cred[0])) {
                            log.logInfo("map." + schema + ": OK login");
                        } else {
                            fail++;
                        }
                    } finally {
                        mc.close();
                    }
                } catch (SQLException ex) {
                    log.logError("map." + schema + ": FAIL login user=" + cred[0] + " " + ex.getMessage());
                    fail++;
                }
            }
            if (cfg.maps.isEmpty()) {
                log.logInfo("map.*: none configured (ok if using --schema-via-alter)");
            }
        } finally {
            pool.close();
        }

        if (fail > 0) {
            log.logError("check FAILED issues=" + fail);
            return 1;
        }
        log.logInfo("check PASSED");
        return 0;
    }

    private static boolean probeSelect(Connection c, String sql, DualLogger log, String label) {
        try (Statement st = c.createStatement();
             ResultSet rs = st.executeQuery(sql)) {
            rs.next();
            log.logInfo("probe " + label + ": OK");
            return true;
        } catch (SQLException e) {
            log.logError("probe " + label + ": FAIL " + e.getMessage());
            return false;
        }
    }

    /** 建临时表再 DROP, 验证登录用户具备建表权限 */
    private static boolean probeCreateDrop(Connection c, DualLogger log) {
        String t = "HTZ_SQL_COLLECT_CHECK_TMP";
        try {
            try (Statement st = c.createStatement()) {
                try {
                    st.execute("DROP TABLE " + t);
                } catch (SQLException ignored) {
                }
                st.execute("CREATE TABLE " + t + " (ID NUMBER)");
                st.execute("DROP TABLE " + t);
            }
            String who = HtzTables.currentUser(c);
            log.logInfo("create_table: OK user=" + who);
            return true;
        } catch (SQLException e) {
            log.logError("create_table: FAIL " + e.getMessage());
            return false;
        }
    }
}
