package com.yashan.sqlcollect;

/**
 * 版本常量与运行时 JDK 兼容检查.
 * 目标字节码: Java 8 (class major 52); 运行需 Java 8+ (8/11/17/21 等均可).
 */
public final class Version {
    public static final String VERSION = "2.0.0-java";

    /** 最低支持的 Java 主版本 (1.8 -> 8) */
    public static final int MIN_JAVA_MAJOR = 8;

    private Version() {}

    /**
     * 解析当前 JVM 主版本号. 兼容 java.specification.version 形如 1.8 / 8 / 11 / 17.
     */
    public static int javaMajorVersion() {
        String spec = System.getProperty("java.specification.version");
        if (spec == null || spec.isEmpty()) {
            String full = System.getProperty("java.version", "0");
            return parseMajor(full);
        }
        return parseMajor(spec);
    }

    /** 解析版本字符串主版本号; 供测试与诊断. */
    public static int parseMajor(String version) {
        if (version == null) {
            return 0;
        }
        String v = version.trim();
        if (v.isEmpty()) {
            return 0;
        }
        // 1.8.0_xxx / 1.8 -> 8
        if (v.startsWith("1.")) {
            int dot = v.indexOf('.', 2);
            String minor = dot < 0 ? v.substring(2) : v.substring(2, dot);
            return parseIntSafe(minor);
        }
        // 11.0.2 / 17 / 21-ea -> 取首段数字
        int end = 0;
        while (end < v.length() && Character.isDigit(v.charAt(end))) {
            end++;
        }
        if (end == 0) {
            return 0;
        }
        return parseIntSafe(v.substring(0, end));
    }

    private static int parseIntSafe(String s) {
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /**
     * 若当前 JVM 低于 MIN_JAVA_MAJOR 则向 stderr 打印说明并退出.
     * @return true 表示通过
     */
    public static boolean ensureRuntimeSupported() {
        int major = javaMajorVersion();
        if (major >= MIN_JAVA_MAJOR) {
            return true;
        }
        String ver = System.getProperty("java.version", "unknown");
        String home = System.getProperty("java.home", "unknown");
        System.err.println("sql-collect " + VERSION
                + " requires Java " + MIN_JAVA_MAJOR + " or newer.");
        System.err.println("  detected java.version=" + ver
                + " (major=" + major + ")");
        System.err.println("  java.home=" + home);
        System.err.println("  Install JDK 8/11/17/21+ and ensure 'java' on PATH.");
        return false;
    }
}
