-- File Name: table_vacuum.sql
-- Purpose: PostgreSQL Table Vacuum
-- Created: 20260516  by  huangtingzhong

-- PostgreSQL Table Bloat Query with AutoVACUUM Threshold Analysis
-- Compatible with PostgreSQL 12+

\prompt 'Please input table name (press Enter for all tables): ' tablename

-- Get current autovacuum settings
WITH autovacuum_settings AS (
    SELECT 
        current_setting('autovacuum_vacuum_threshold')::int AS vacuum_threshold,
        current_setting('autovacuum_vacuum_scale_factor')::numeric AS vacuum_scale_factor,
        current_setting('autovacuum_analyze_threshold')::int AS analyze_threshold,
        current_setting('autovacuum_analyze_scale_factor')::numeric AS analyze_scale_factor,
        current_setting('autovacuum_vacuum_insert_threshold')::int AS vacuum_insert_threshold,
        current_setting('autovacuum_vacuum_insert_scale_factor')::numeric AS vacuum_insert_scale_factor,
        current_setting('autovacuum_vacuum_cost_delay')::int AS vacuum_cost_delay,
        current_setting('autovacuum_vacuum_cost_limit')::int AS vacuum_cost_limit
),
table_stats AS (
    SELECT 
        schemaname,
        relname,
        pg_total_relation_size(schemaname||'.'||relname) AS total_bytes,
        pg_relation_size(schemaname||'.'||relname) AS table_bytes,
        pg_total_relation_size(schemaname||'.'||relname) - pg_relation_size(schemaname||'.'||relname) AS index_bytes,
        n_tup_ins,
        n_tup_upd,
        n_tup_del,
        n_live_tup,
        n_dead_tup,
        n_ins_since_vacuum,
        n_mod_since_analyze,
        last_vacuum,
        last_autovacuum,
        last_analyze,
        last_autoanalyze,
        vacuum_count,
        autovacuum_count,
        analyze_count,
        autoanalyze_count,
        -- Calculate autovacuum thresholds
        CASE 
            WHEN n_live_tup = 0 THEN 0
            ELSE GREATEST(
                avs.vacuum_threshold,
                avs.vacuum_threshold + (n_live_tup * avs.vacuum_scale_factor)::int
            )
        END AS vacuum_trigger_threshold,
        CASE 
            WHEN n_live_tup = 0 THEN 0
            ELSE GREATEST(
                avs.analyze_threshold,
                avs.analyze_threshold + (n_live_tup * avs.analyze_scale_factor)::int
            )
        END AS analyze_trigger_threshold,
        CASE 
            WHEN n_live_tup = 0 THEN 0
            ELSE GREATEST(
                avs.vacuum_insert_threshold,
                avs.vacuum_insert_threshold + (n_live_tup * avs.vacuum_insert_scale_factor)::int
            )
        END AS vacuum_insert_trigger_threshold,
        -- Calculate percentages
        CASE 
            WHEN n_live_tup + n_dead_tup > 0 THEN 
                ROUND((n_dead_tup::numeric / (n_live_tup + n_dead_tup) * 100), 2)
            ELSE 0
        END AS bloat_pct,
        CASE 
            WHEN n_live_tup > 0 AND GREATEST(
                avs.vacuum_threshold,
                avs.vacuum_threshold + (n_live_tup * avs.vacuum_scale_factor)::int
            ) > 0 THEN
                ROUND((n_dead_tup::numeric / GREATEST(
                    avs.vacuum_threshold,
                    avs.vacuum_threshold + (n_live_tup * avs.vacuum_scale_factor)::int
                ) * 100), 2)
            ELSE 0
        END AS vacuum_trigger_pct,
        CASE 
            WHEN n_live_tup > 0 AND GREATEST(
                avs.analyze_threshold,
                avs.analyze_threshold + (n_live_tup * avs.analyze_scale_factor)::int
            ) > 0 THEN
                ROUND(((n_mod_since_analyze)::numeric / GREATEST(
                    avs.analyze_threshold,
                    avs.analyze_threshold + (n_live_tup * avs.analyze_scale_factor)::int
                )) * 100, 2)
            ELSE 0
        END AS analyze_trigger_pct,
        CASE 
            WHEN n_live_tup > 0 AND GREATEST(
                avs.vacuum_insert_threshold,
                avs.vacuum_insert_threshold + (n_live_tup * avs.vacuum_insert_scale_factor)::int
            ) > 0 THEN
                ROUND((n_ins_since_vacuum::numeric / GREATEST(
                    avs.vacuum_insert_threshold,
                    avs.vacuum_insert_threshold + (n_live_tup * avs.vacuum_insert_scale_factor)::int
                )) * 100, 2)
            ELSE 0
        END AS vacuum_insert_trigger_pct
    FROM pg_stat_user_tables s
    CROSS JOIN autovacuum_settings avs
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
)
SELECT 
    schemaname AS schema,
    relname AS name,
    CASE 
        WHEN total_bytes >= 1024*1024*1024 THEN ROUND(total_bytes::numeric/(1024*1024*1024), 2) || 'G'
        WHEN total_bytes >= 1024*1024 THEN ROUND(total_bytes::numeric/(1024*1024), 2) || 'M'
        WHEN total_bytes >= 1024 THEN ROUND(total_bytes::numeric/1024, 2) || 'K'
        ELSE total_bytes || 'B'
    END AS total,
    CASE 
        WHEN table_bytes >= 1024*1024*1024 THEN ROUND(table_bytes::numeric/(1024*1024*1024), 2) || 'G'
        WHEN table_bytes >= 1024*1024 THEN ROUND(table_bytes::numeric/(1024*1024), 2) || 'M'
        WHEN table_bytes >= 1024 THEN ROUND(table_bytes::numeric/1024, 2) || 'K'
        ELSE table_bytes || 'B'
    END AS table,
    CASE 
        WHEN index_bytes >= 1024*1024*1024 THEN ROUND(index_bytes::numeric/(1024*1024*1024), 2) || 'G'
        WHEN index_bytes >= 1024*1024 THEN ROUND(index_bytes::numeric/(1024*1024), 2) || 'M'
        WHEN index_bytes >= 1024 THEN ROUND(index_bytes::numeric/1024, 2) || 'K'
        ELSE index_bytes || 'B'
    END AS index,
   -- CASE
   --     WHEN n_tup_ins >= 1000000000 THEN ROUND(n_tup_ins::numeric/1000000000, 2) || 'Y'
   --     WHEN n_tup_ins >= 1000000 THEN ROUND(n_tup_ins::numeric/1000000, 2) || 'M'
   --     WHEN n_tup_ins >= 10000 THEN ROUND(n_tup_ins::numeric/10000, 2) || 'W'
   --     WHEN n_tup_ins >= 1000 THEN ROUND(n_tup_ins::numeric/1000, 2) || 'K'
   --     ELSE n_tup_ins::text
   -- END AS ins,
    CASE 
        WHEN n_ins_since_vacuum >= 1000000000 THEN ROUND(n_ins_since_vacuum::numeric/1000000000, 2) || 'Y'
        WHEN n_ins_since_vacuum >= 1000000 THEN ROUND(n_ins_since_vacuum::numeric/1000000, 2) || 'M'
        WHEN n_ins_since_vacuum >= 10000 THEN ROUND(n_ins_since_vacuum::numeric/10000, 2) || 'W'
        WHEN n_ins_since_vacuum >= 1000 THEN ROUND(n_ins_since_vacuum::numeric/1000, 2) || 'K'
        ELSE n_ins_since_vacuum::text
    END AS ins_vac,
  --  CASE
  --      WHEN n_tup_upd >= 1000000000 THEN ROUND(n_tup_upd::numeric/1000000000, 2) || 'Y'
  --      WHEN n_tup_upd >= 1000000 THEN ROUND(n_tup_upd::numeric/1000000, 2) || 'M'
  --      WHEN n_tup_upd >= 10000 THEN ROUND(n_tup_upd::numeric/10000, 2) || 'W'
  --      WHEN n_tup_upd >= 1000 THEN ROUND(n_tup_upd::numeric/1000, 2) || 'K'
  --      ELSE n_tup_upd::text
  --  END AS upd,
  --  CASE
  --      WHEN n_tup_del >= 1000000000 THEN ROUND(n_tup_del::numeric/1000000000, 2) || 'Y'
  --      WHEN n_tup_del >= 1000000 THEN ROUND(n_tup_del::numeric/1000000, 2) || 'M'
  --      WHEN n_tup_del >= 10000 THEN ROUND(n_tup_del::numeric/10000, 2) || 'W'
  --      WHEN n_tup_del >= 1000 THEN ROUND(n_tup_del::numeric/1000, 2) || 'K'
  --      ELSE n_tup_del::text
  --  END AS del,
    CASE 
        WHEN n_live_tup >= 1000000000 THEN ROUND(n_live_tup::numeric/1000000000, 2) || 'Y'
        WHEN n_live_tup >= 1000000 THEN ROUND(n_live_tup::numeric/1000000, 2) || 'M'
        WHEN n_live_tup >= 10000 THEN ROUND(n_live_tup::numeric/10000, 2) || 'W'
        WHEN n_live_tup >= 1000 THEN ROUND(n_live_tup::numeric/1000, 2) || 'K'
        ELSE n_live_tup::text
    END AS live,
    CASE 
        WHEN n_dead_tup >= 1000000000 THEN ROUND(n_dead_tup::numeric/1000000000, 2) || 'Y'
        WHEN n_dead_tup >= 1000000 THEN ROUND(n_dead_tup::numeric/1000000, 2) || 'M'
        WHEN n_dead_tup >= 10000 THEN ROUND(n_dead_tup::numeric/10000, 2) || 'W'
        WHEN n_dead_tup >= 1000 THEN ROUND(n_dead_tup::numeric/1000, 2) || 'K'
        ELSE n_dead_tup::text
    END AS dead,
    bloat_pct || '%' AS bloat_pct,
    vacuum_trigger_pct || '%' AS vac_pct,
    analyze_trigger_pct || '%' AS ana_pct,
    vacuum_insert_trigger_pct || '%' AS vac_i_pct,
    CASE 
        WHEN vacuum_trigger_threshold >= 1000000000 THEN ROUND(vacuum_trigger_threshold::numeric/1000000000, 2) || 'Y'
        WHEN vacuum_trigger_threshold >= 1000000 THEN ROUND(vacuum_trigger_threshold::numeric/1000000, 2) || 'M'
        WHEN vacuum_trigger_threshold >= 10000 THEN ROUND(vacuum_trigger_threshold::numeric/10000, 2) || 'W'
        WHEN vacuum_trigger_threshold >= 1000 THEN ROUND(vacuum_trigger_threshold::numeric/1000, 2) || 'K'
        ELSE vacuum_trigger_threshold::text
    END AS vac_t,
    CASE 
        WHEN analyze_trigger_threshold >= 1000000000 THEN ROUND(analyze_trigger_threshold::numeric/1000000000, 2) || 'Y'
        WHEN analyze_trigger_threshold >= 1000000 THEN ROUND(analyze_trigger_threshold::numeric/1000000, 2) || 'M'
        WHEN analyze_trigger_threshold >= 10000 THEN ROUND(analyze_trigger_threshold::numeric/10000, 2) || 'W'
        WHEN analyze_trigger_threshold >= 1000 THEN ROUND(analyze_trigger_threshold::numeric/1000, 2) || 'K'
        ELSE analyze_trigger_threshold::text
    END AS ana_t,
    CASE 
        WHEN vacuum_insert_trigger_threshold >= 1000000000 THEN ROUND(vacuum_insert_trigger_threshold::numeric/1000000000, 2) || 'Y'
        WHEN vacuum_insert_trigger_threshold >= 1000000 THEN ROUND(vacuum_insert_trigger_threshold::numeric/1000000, 2) || 'M'
        WHEN vacuum_insert_trigger_threshold >= 10000 THEN ROUND(vacuum_insert_trigger_threshold::numeric/10000, 2) || 'W'
        WHEN vacuum_insert_trigger_threshold >= 1000 THEN ROUND(vacuum_insert_trigger_threshold::numeric/1000, 2) || 'K'
        ELSE vacuum_insert_trigger_threshold::text
    END AS vac_i_t,
    TO_CHAR(last_vacuum, 'MM-DD HH24:MI') AS last_vac,
    TO_CHAR(last_autovacuum, 'MM-DD HH24:MI') AS last_a_vac,
    TO_CHAR(last_analyze, 'MM-DD HH24:MI') AS last_ana,
    TO_CHAR(last_autoanalyze, 'MM-DD HH24:MI') AS last_a_ana,
    vacuum_count AS vac_cnt,
    autovacuum_count AS a_vac_cnt,
    analyze_count AS ana_cnt,
    autoanalyze_count AS a_ana_cnt
FROM table_stats
WHERE (:'tablename' IS NULL OR :'tablename' = '' OR relname ILIKE '%' || :'tablename' || '%')
ORDER BY 
    CASE WHEN n_dead_tup >= vacuum_trigger_threshold THEN 0 ELSE 1 END,
    n_dead_tup DESC NULLS LAST;
