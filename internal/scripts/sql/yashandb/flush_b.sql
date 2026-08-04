-- File Name: flush_b.sql
-- Purpose: YashanDB Flush buffer cache
-- Created: 20260731  by  huangtingzhong
-- 等价于 ALTER SYSTEM FLUSH BUFFER_CACHE；清空数据缓存块。
-- 常用于：性能测试时强制物理读、排查缓存命中带来的读时间偏差。
ALTER SYSTEM FLUSH BUFFER_CACHE;
