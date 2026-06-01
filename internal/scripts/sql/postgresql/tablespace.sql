-- File Name: tablespace.sql
-- Purpose: PostgreSQL Tablespace
-- Created: 20260516  by  huangtingzhong

-- PostgreSQL Tablespace Combined Information Query
-- Combines tablespace info and capacity statistics in one query
-- All columns are in English

SELECT 
    ts.spcname AS name,
    CASE 
        WHEN pg_tablespace_location(ts.oid) IS NOT NULL AND pg_tablespace_location(ts.oid) != '' THEN pg_tablespace_location(ts.oid)
        WHEN ts.spcname = 'pg_default' THEN current_setting('data_directory') || '/base'
        WHEN ts.spcname = 'pg_global' THEN current_setting('data_directory') || '/global'
        ELSE 'System Default'
    END AS path,
    pg_get_userbyid(ts.spcowner) AS owner,
    CASE 
        WHEN ts.spcname = 'pg_default' THEN 'Default'
        WHEN ts.spcname = 'pg_global' THEN 'Global'
        ELSE 'User'
    END AS type,
    COALESCE(table_stats.table_count, 0) AS tables,
    pg_size_pretty(pg_tablespace_size(ts.spcname)) AS total,
    COALESCE(pg_size_pretty(table_stats.total_size_bytes), '0 bytes') AS used,
    COALESCE(pg_size_pretty(table_stats.table_size_bytes), '0 bytes') AS data,
    COALESCE(pg_size_pretty(table_stats.index_size_bytes), '0 bytes') AS index,
    CASE 
        WHEN pg_tablespace_size(ts.spcname) > 0 AND table_stats.total_size_bytes > 0 THEN
            ROUND((table_stats.total_size_bytes::numeric / pg_tablespace_size(ts.spcname)::numeric) * 100, 2) || '%'
        ELSE '0%'
    END AS usage
FROM pg_tablespace ts
LEFT JOIN (
    SELECT 
        COALESCE(tablespace, 'pg_default') AS tablespace_name,
        COUNT(*) AS table_count,
        SUM(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size_bytes,
        SUM(pg_relation_size(schemaname||'.'||tablename)) AS table_size_bytes,
        SUM(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS index_size_bytes
    FROM pg_tables 
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
    GROUP BY tablespace
) table_stats ON ts.spcname = table_stats.tablespace_name
ORDER BY pg_tablespace_size(ts.spcname) DESC NULLS LAST;
