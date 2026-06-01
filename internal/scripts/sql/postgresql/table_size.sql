-- File Name: table_size.sql
-- Purpose: PostgreSQL Show table and index size with LOB
-- Created: 20260516  by  huangtingzhong

-- PostgreSQL Enhanced Table Information Query
-- Enhanced version of \d+ with index sizes and TOAST table sizes
-- All columns are in English

\prompt 'please input table name: ' tablename

SELECT 
    pg_get_userbyid(c.relowner) AS owner,
    t.schemaname AS schema,
    t.tablename AS name,
    CASE 
        WHEN c.relkind = 'r' THEN 'table'
        WHEN c.relkind = 'v' THEN 'view'
        WHEN c.relkind = 'm' THEN 'materialized view'
        WHEN c.relkind = 'S' THEN 'sequence'
        WHEN c.relkind = 'f' THEN 'foreign table'
        ELSE 'unknown'
    END AS type,
    CASE 
        WHEN c.relpersistence = 'p' THEN 'permanent'
        WHEN c.relpersistence = 't' THEN 'temporary'
        WHEN c.relpersistence = 'u' THEN 'unlogged'
        ELSE 'unknown'
    END AS persistence,
    COALESCE(am.amname, 'heap') AS access_method,
    pg_size_pretty(pg_total_relation_size(t.schemaname||'.'||t.tablename)) AS total,
    pg_size_pretty(pg_relation_size(t.schemaname||'.'||t.tablename)) AS table,
    pg_size_pretty(pg_total_relation_size(t.schemaname||'.'||t.tablename) - pg_relation_size(t.schemaname||'.'||t.tablename)) AS index,
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_class WHERE relname = t.tablename||'_toast' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = t.schemaname))
        THEN pg_size_pretty(pg_relation_size(t.schemaname||'.'||t.tablename||'_toast'))
        ELSE '0 bytes'
    END AS toast,
    CASE 
        WHEN EXISTS (SELECT 1 FROM pg_class WHERE relname = t.tablename||'_toast_index' AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = t.schemaname))
        THEN pg_size_pretty(pg_relation_size(t.schemaname||'.'||t.tablename||'_toast_index'))
        ELSE '0 bytes'
    END AS toast_idx
FROM pg_tables t
LEFT JOIN pg_class c ON c.relname = t.tablename AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = t.schemaname)
LEFT JOIN pg_am am ON c.relam = am.oid
WHERE t.schemaname NOT IN ('information_schema', 'pg_catalog')
AND (:'tablename' IS NULL OR :'tablename' = '' OR t.tablename ILIKE '%' || :'tablename' || '%')
ORDER BY pg_total_relation_size(t.schemaname||'.'||t.tablename) DESC;
