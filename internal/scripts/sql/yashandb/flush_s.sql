-- File Name: flush_s.sql
-- Purpose: YashanDB Flush shared pool
-- Created: 20260731  by  huangtingzhong
-- 等价于 ALTER SYSTEM FLUSH SHARED_POOL；清空共享池游标，强制重新硬解析。
-- 常用于：让新创建的 sqlmap/outline 立即生效、排查 cursor 复用问题。
ALTER SYSTEM FLUSH SHARED_POOL;
