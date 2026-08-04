package com.yashan.sqlcollect.db;

import com.yashan.sqlcollect.config.JdbcConfig;
import com.yashan.sqlcollect.log.DualLogger;

import java.io.Reader;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * JDBC 会话: 优先从 {@link JdbcPool} 借连接, 关闭时归还池 (或无池时真正断开).
 */
public class JdbcSession implements AutoCloseable {

    private final Connection connection;
    private final DualLogger log;
    private final JdbcPool pool;
    private final boolean ownsPoolClose;

    public JdbcSession(JdbcConfig cfg) throws SQLException, ClassNotFoundException {
        this(cfg, null, null);
    }

    public JdbcSession(JdbcConfig cfg, DualLogger log) throws SQLException, ClassNotFoundException {
        this(cfg, log, null);
    }

    /**
     * @param pool 若非 null 则从池借连接; 若 null 则创建一次性私有池(单连接)并在 close 时关掉
     */
    public JdbcSession(JdbcConfig cfg, DualLogger log, JdbcPool pool)
            throws SQLException, ClassNotFoundException {
        this.log = log;
        if (pool != null) {
            this.pool = pool;
            this.ownsPoolClose = false;
        } else {
            this.pool = new JdbcPool(log, 1);
            this.ownsPoolClose = true;
        }
        long t0 = System.currentTimeMillis();
        if (log != null) {
            log.logStep("jdbc_connect", cfg.user + "@" + cfg.jdbcUrl);
            log.logDbg("jdbc connecting url=" + cfg.jdbcUrl + " user=" + cfg.user
                    + " schema_via_alter=" + cfg.schemaViaAlter
                    + " current_schema=" + (cfg.currentSchema == null ? "" : cfg.currentSchema)
                    + " pool=" + (ownsPoolClose ? "private" : "shared"));
        }
        try {
            Class.forName("com.yashandb.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            if (ownsPoolClose) {
                this.pool.close();
            }
            throw e;
        }
        try {
            connection = this.pool.borrow(cfg.jdbcUrl, cfg.user, cfg.password);
        } catch (SQLException e) {
            if (ownsPoolClose) {
                this.pool.close();
            }
            throw e;
        }
        if (log != null) {
            log.commandResult("jdbc", "connect", 0, "user=" + cfg.user,
                    (System.currentTimeMillis() - t0) / 1000.0);
        }
        if (cfg.schemaViaAlter && cfg.currentSchema != null && !cfg.currentSchema.trim().isEmpty()) {
            setCurrentSchema(cfg.currentSchema.trim());
        }
    }

    public Connection getConnection() {
        return connection;
    }

    public JdbcPool getPool() {
        return pool;
    }

    public void setCurrentSchema(String schema) throws SQLException {
        if (schema == null || schema.isEmpty()) {
            return;
        }
        String q = schema.replace("\"", "\"\"");
        String sql = "ALTER SESSION SET CURRENT_SCHEMA = \"" + q + "\"";
        if (log != null) {
            log.logStep("alter_session", "CURRENT_SCHEMA=" + schema);
            log.logDbg("jdbc sql [alter_session]: " + sql);
        }
        Statement st = connection.createStatement();
        try {
            st.execute(sql);
            if (log != null) {
                log.logDbg("CURRENT_SCHEMA set to " + schema);
            }
        } finally {
            st.close();
        }
    }

    public static String readClob(Clob c) throws SQLException {
        if (c == null) {
            return "";
        }
        Reader r = c.getCharacterStream();
        StringBuilder sb = new StringBuilder();
        char[] buf = new char[8192];
        try {
            int n;
            while ((n = r.read(buf)) >= 0) {
                sb.append(buf, 0, n);
            }
            r.close();
        } catch (java.io.IOException e) {
            throw new SQLException("read clob failed", e);
        }
        return sb.toString();
    }

    public void execute(String sql) throws SQLException {
        Statement st = connection.createStatement();
        try {
            st.execute(sql);
        } finally {
            st.close();
        }
    }

    @Override
    public void close() {
        if (connection != null) {
            try {
                connection.close(); // 池代理: 归还
            } catch (SQLException ignored) {
            }
        }
        if (ownsPoolClose && pool != null) {
            pool.close();
        }
    }
}
