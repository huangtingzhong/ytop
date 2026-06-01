-- File Name: sql_text_by_full.sql
-- Purpose: PostgreSQL SQL Text By Full
-- Created: 20260516  by  huangtingzhong

WITH formatted_data AS (
    SELECT 
        d.datname AS database_name,
        u.usename AS username,
        s.query AS sql_statement,
        s.calls AS execution_count,
        CASE 
            WHEN s.calls >= 100000000 THEN ROUND(s.calls::numeric / 100000000, 2) || 'Y'
            WHEN s.calls >= 10000 THEN ROUND(s.calls::numeric / 10000, 2) || 'W'
            WHEN s.calls >= 1000 THEN ROUND(s.calls::numeric / 1000, 2) || 'K'
            ELSE s.calls::text
        END AS formatted_execution_count,
        CASE 
            WHEN (s.total_exec_time / NULLIF(s.calls, 0)) >= 3600000 THEN ROUND(((s.total_exec_time / NULLIF(s.calls, 0)) / 3600000)::numeric, 2) || 'H'
            WHEN (s.total_exec_time / NULLIF(s.calls, 0)) >= 60000 THEN ROUND(((s.total_exec_time / NULLIF(s.calls, 0)) / 60000)::numeric, 2) || 'M'
            WHEN (s.total_exec_time / NULLIF(s.calls, 0)) >= 1000 THEN ROUND(((s.total_exec_time / NULLIF(s.calls, 0)) / 1000)::numeric, 2) || 'S'
            ELSE ROUND((s.total_exec_time / NULLIF(s.calls, 0))::numeric, 2) || 'MS'
        END AS avg_execution_time_per_call,
        CASE 
            WHEN s.max_exec_time >= 3600000 THEN ROUND((s.max_exec_time / 3600000)::numeric, 2) || 'H'
            WHEN s.max_exec_time >= 60000 THEN ROUND((s.max_exec_time / 60000)::numeric, 2) || 'M'
            WHEN s.max_exec_time >= 1000 THEN ROUND((s.max_exec_time / 1000)::numeric, 2) || 'S'
            ELSE ROUND(s.max_exec_time::numeric, 2) || 'MS'
        END AS max_execution_time,
        CASE 
            WHEN s.min_exec_time >= 3600000 THEN ROUND((s.min_exec_time / 3600000)::numeric, 2) || 'H'
            WHEN s.min_exec_time >= 60000 THEN ROUND((s.min_exec_time / 60000)::numeric, 2) || 'M'
            WHEN s.min_exec_time >= 1000 THEN ROUND((s.min_exec_time / 1000)::numeric, 2) || 'S'
            ELSE ROUND(s.min_exec_time::numeric, 2) || 'MS'
        END AS min_execution_time,
        CASE 
            WHEN s.stddev_exec_time >= 3600000 THEN ROUND((s.stddev_exec_time / 3600000)::numeric, 2) || 'H'
            WHEN s.stddev_exec_time >= 60000 THEN ROUND((s.stddev_exec_time / 60000)::numeric, 2) || 'M'
            WHEN s.stddev_exec_time >= 1000 THEN ROUND((s.stddev_exec_time / 1000)::numeric, 2) || 'S'
            ELSE ROUND(s.stddev_exec_time::numeric, 2) || 'MS'
        END AS stddev_execution_time,
        ROUND(s.rows::numeric / NULLIF(s.calls, 0), 2) AS avg_rows_per_call,
        ROUND(s.shared_blks_hit::numeric / NULLIF(s.calls, 0), 2) AS avg_shared_blocks_hit_per_call,
        ROUND(s.shared_blks_read::numeric / NULLIF(s.calls, 0), 2) AS avg_shared_blocks_read_per_call,
        ROUND(s.shared_blks_written::numeric / NULLIF(s.calls, 0), 2) AS avg_shared_blocks_written_per_call,
        ROUND(s.temp_blks_read::numeric / NULLIF(s.calls, 0), 2) AS avg_temp_blocks_read_per_call,
        ROUND(s.temp_blks_written::numeric / NULLIF(s.calls, 0), 2) AS avg_temp_blocks_written_per_call,
        p.plan AS execution_plan,
        p.planid AS plan_id,
        p.queryid AS query_id,
        p.calls AS plan_calls,
        CASE 
            WHEN (p.total_time / NULLIF(p.calls, 0)) >= 3600000 THEN ROUND(((p.total_time / NULLIF(p.calls, 0)) / 3600000)::numeric, 2) || 'H'
            WHEN (p.total_time / NULLIF(p.calls, 0)) >= 60000 THEN ROUND(((p.total_time / NULLIF(p.calls, 0)) / 60000)::numeric, 2) || 'M'
            WHEN (p.total_time / NULLIF(p.calls, 0)) >= 1000 THEN ROUND(((p.total_time / NULLIF(p.calls, 0)) / 1000)::numeric, 2) || 'S'
            ELSE ROUND((p.total_time / NULLIF(p.calls, 0))::numeric, 2) || 'MS'
        END AS avg_plan_time_per_call,
        p.mean_time AS plan_mean_time_ms
    FROM pg_stat_statements s
    LEFT JOIN pg_store_plans p ON s.queryid = p.queryid
    LEFT JOIN pg_database d ON s.dbid = d.oid
    LEFT JOIN pg_user u ON s.userid = u.usesysid
    WHERE plan LIKE '%Seq Scan%'
    AND plan NOT LIKE '%pg_store_plans%'
    AND regexp_replace(plan, '.*Seq Scan on ([^ ]+).*', '\1') !~ '^(pg_|information_schema)'
)
SELECT 
    database_name,
		username,
    sql_statement,
    formatted_execution_count AS execution_count,
    avg_execution_time_per_call,
    max_execution_time,
    min_execution_time,
    stddev_execution_time,
    avg_rows_per_call,
    avg_shared_blocks_hit_per_call,
    avg_shared_blocks_read_per_call,
    avg_shared_blocks_written_per_call,
    avg_temp_blocks_read_per_call,
    avg_temp_blocks_written_per_call,
    execution_plan,
    plan_id,
    query_id,
    plan_calls,
    avg_plan_time_per_call,
    plan_mean_time_ms
FROM formatted_data
ORDER BY (SELECT total_exec_time / NULLIF(calls, 0) FROM pg_stat_statements WHERE query = formatted_data.sql_statement LIMIT 1) DESC
LIMIT 50;
