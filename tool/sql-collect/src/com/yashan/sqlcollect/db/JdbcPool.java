package com.yashan.sqlcollect.db;

import com.yashan.sqlcollect.log.DualLogger;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 简易 JDBC 连接池 (无第三方依赖): 按 jdbcUrl+user 复用连接, 减少重复登录.
 * close() 经代理归还池; pool.close() 时真正断开.
 */
public final class JdbcPool implements AutoCloseable {

    public static final int DEFAULT_MAX_IDLE_PER_USER = 4;

    private final DualLogger log;
    private final int maxIdlePerUser;
    private final Map<String, ArrayDeque<Connection>> idle =
            new ConcurrentHashMap<String, ArrayDeque<Connection>>();
    private final Set<Connection> all =
            Collections.newSetFromMap(new ConcurrentHashMap<Connection, Boolean>());
    private final Set<Connection> borrowed =
            Collections.newSetFromMap(new ConcurrentHashMap<Connection, Boolean>());
    private volatile boolean closed;

    public JdbcPool() {
        this(null, DEFAULT_MAX_IDLE_PER_USER);
    }

    public JdbcPool(DualLogger log) {
        this(log, DEFAULT_MAX_IDLE_PER_USER);
    }

    public JdbcPool(DualLogger log, int maxIdlePerUser) {
        this.log = log;
        this.maxIdlePerUser = maxIdlePerUser < 1 ? 1 : maxIdlePerUser;
        try {
            Class.forName("com.yashandb.jdbc.Driver");
        } catch (ClassNotFoundException e) {
            // 延迟到 borrow 再失败
        }
    }

    public Connection borrow(String jdbcUrl, String user, String password) throws SQLException {
        if (closed) {
            throw new SQLException("jdbc pool closed");
        }
        if (jdbcUrl == null || jdbcUrl.isEmpty()) {
            throw new SQLException("jdbc url empty");
        }
        if (user == null) {
            user = "";
        }
        if (password == null) {
            password = "";
        }
        String key = poolKey(jdbcUrl, user, password);
        Connection raw = pollIdle(key);
        if (raw == null) {
            long t0 = System.currentTimeMillis();
            if (log != null) {
                log.logDbg("jdbc pool create url=" + jdbcUrl + " user=" + user);
            }
            try {
                Class.forName("com.yashandb.jdbc.Driver");
            } catch (ClassNotFoundException e) {
                throw new SQLException("JDBC driver not found", e);
            }
            raw = DriverManager.getConnection(jdbcUrl, user, password);
            all.add(raw);
            if (log != null) {
                log.logDbg("jdbc pool created user=" + user
                        + " in " + String.format(Locale.US, "%.3f",
                        (System.currentTimeMillis() - t0) / 1000.0) + "s"
                        + " idle_keys=" + idle.size() + " live=" + all.size());
            }
        } else if (log != null) {
            log.logDbg("jdbc pool reuse user=" + user);
        }
        borrowed.add(raw);
        return wrap(raw, key, user);
    }

    public void release(Connection c) {
        if (c == null) {
            return;
        }
        // 若传入的是代理, InvocationHandler 会处理; 此处兼容裸连接
        try {
            if (Proxy.isProxyClass(c.getClass())) {
                c.close();
                return;
            }
        } catch (SQLException ignored) {
        }
        releaseRaw(poolKeyGuess(c), c, null);
    }

    @Override
    public void close() {
        if (closed) {
            return;
        }
        closed = true;
        for (ArrayDeque<Connection> q : idle.values()) {
            synchronized (q) {
                while (!q.isEmpty()) {
                    closeQuiet(q.pollFirst());
                }
            }
        }
        idle.clear();
        for (Connection c : new HashSet<Connection>(all)) {
            closeQuiet(c);
        }
        all.clear();
        borrowed.clear();
        if (log != null) {
            log.logDbg("jdbc pool closed");
        }
    }

    public int idleCount() {
        int n = 0;
        for (ArrayDeque<Connection> q : idle.values()) {
            synchronized (q) {
                n += q.size();
            }
        }
        return n;
    }

    public int liveCount() {
        return all.size();
    }

    /** 池键含 password, 避免错口令复用正确连接 */
    static String poolKey(String jdbcUrl, String user, String password) {
        return jdbcUrl + "\0"
                + (user == null ? "" : user) + "\0"
                + (password == null ? "" : password);
    }

    private Connection pollIdle(String key) {
        ArrayDeque<Connection> q = idle.get(key);
        if (q == null) {
            return null;
        }
        synchronized (q) {
            while (!q.isEmpty()) {
                Connection c = q.pollFirst();
                if (c == null) {
                    continue;
                }
                if (isUsable(c)) {
                    return c;
                }
                closeQuiet(c);
                all.remove(c);
            }
        }
        return null;
    }

    private void releaseRaw(String key, Connection raw, String loginUser) {
        if (raw == null) {
            return;
        }
        borrowed.remove(raw);
        if (closed) {
            closeQuiet(raw);
            all.remove(raw);
            return;
        }
        try {
            if (raw.isClosed()) {
                all.remove(raw);
                return;
            }
        } catch (SQLException e) {
            closeQuiet(raw);
            all.remove(raw);
            return;
        }
        resetForReuse(raw, loginUser);
        ArrayDeque<Connection> q = idle.get(key);
        if (q == null) {
            q = new ArrayDeque<Connection>();
            ArrayDeque<Connection> prev = idle.putIfAbsent(key, q);
            if (prev != null) {
                q = prev;
            }
        }
        synchronized (q) {
            if (q.size() < maxIdlePerUser) {
                q.addLast(raw);
                if (log != null) {
                    // key = url\0user\0password — 日志只打 user 段
                    String[] parts = key.split("\0", -1);
                    String u = parts.length > 1 ? parts[1] : "?";
                    log.logDbg("jdbc pool release->idle user=" + u + " idle=" + q.size());
                }
                return;
            }
        }
        closeQuiet(raw);
        all.remove(raw);
    }

    /**
     * 归还前复位事务状态. 不改 CURRENT_SCHEMA:
     * collect 全程单用户, 不应切 schema; 以 SYS 登录时 ALTER CURRENT_SCHEMA=SYS 会触发 YAS-02012.
     * replay 的 schema-via-alter 由执行路径按条 SQL 自行 SET.
     */
    private void resetForReuse(Connection c, String loginUser) {
        try {
            c.clearWarnings();
        } catch (SQLException ignored) {
        }
        try {
            if (!c.getAutoCommit()) {
                try {
                    c.rollback();
                } catch (SQLException ignored) {
                }
                c.setAutoCommit(true);
            }
        } catch (SQLException ignored) {
        }
    }

    private boolean isUsable(Connection c) {
        try {
            if (c == null || c.isClosed()) {
                return false;
            }
            try {
                return c.isValid(3);
            } catch (AbstractMethodError e) {
                return true;
            } catch (SQLException e) {
                // isValid 抛异常视为不可用, 由池关闭并新建
                return false;
            }
        } catch (SQLException e) {
            return false;
        }
    }

    private Connection wrap(final Connection raw, final String key, final String loginUser) {
        final JdbcPool self = this;
        InvocationHandler h = new InvocationHandler() {
            private boolean returned;

            public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                String name = method.getName();
                if ("close".equals(name)) {
                    if (!returned) {
                        returned = true;
                        self.releaseRaw(key, raw, loginUser);
                    }
                    return null;
                }
                if ("isClosed".equals(name)) {
                    if (returned || self.closed) {
                        return Boolean.TRUE;
                    }
                    return Boolean.valueOf(raw.isClosed());
                }
                if ("equals".equals(name)) {
                    return Boolean.valueOf(proxy == args[0]);
                }
                if ("hashCode".equals(name)) {
                    return Integer.valueOf(System.identityHashCode(proxy));
                }
                if ("toString".equals(name)) {
                    return "PooledConnection(" + loginUser + ")@" + Integer.toHexString(System.identityHashCode(proxy));
                }
                if (returned) {
                    throw new SQLException("connection returned to pool");
                }
                try {
                    return method.invoke(raw, args);
                } catch (java.lang.reflect.InvocationTargetException e) {
                    Throwable c = e.getCause();
                    if (c != null) {
                        throw c;
                    }
                    throw e;
                }
            }
        };
        return (Connection) Proxy.newProxyInstance(
                Connection.class.getClassLoader(),
                new Class[] {Connection.class},
                h);
    }

    private String poolKeyGuess(Connection c) {
        return "unknown\0";
    }

    private void closeQuiet(Connection c) {
        if (c == null) {
            return;
        }
        try {
            if (!c.isClosed()) {
                c.close();
            }
        } catch (SQLException ignored) {
        }
        all.remove(c);
        borrowed.remove(c);
    }
}
