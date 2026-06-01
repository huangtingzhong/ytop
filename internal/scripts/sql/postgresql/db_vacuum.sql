-- File Name: db_vacuum.sql
-- Purpose: PostgreSQL DB Vacuum
-- Created: 20260516  by  huangtingzhong

WITH v AS (
  SELECT * FROM
    (SELECT setting AS autovacuum_vacuum_scale_factor FROM pg_settings WHERE name = 'autovacuum_vacuum_scale_factor') vsf,
    (SELECT setting AS autovacuum_vacuum_threshold FROM pg_settings WHERE name = 'autovacuum_vacuum_threshold') vth,
    (SELECT setting AS autovacuum_analyze_scale_factor FROM pg_settings WHERE name = 'autovacuum_analyze_scale_factor') asf,
    (SELECT setting AS autovacuum_analyze_threshold FROM pg_settings WHERE name = 'autovacuum_analyze_threshold') ath
),
t AS (
    SELECT
        c.reltuples,u.*
    FROM
        pg_stat_user_tables u, pg_class c, pg_namespace n
    WHERE n.oid = c.relnamespace
        AND c.relname = u.relname
        AND n.nspname = u.schemaname
)
SELECT
    schemaname,
    relname,
    autovacuum_vacuum_scale_factor,
    autovacuum_vacuum_threshold,
    autovacuum_analyze_scale_factor,
    autovacuum_analyze_threshold,
    n_live_tup,
    reltuples,
    autovacuum_analyze_trigger,
    n_mod_since_analyze,
    autovacuum_analyze_trigger - n_mod_since_analyze AS rows_to_mod_before_auto_analyze,
    last_autoanalyze,
    autovacuum_vacuum_trigger,
    n_dead_tup,
    autovacuum_vacuum_trigger - n_dead_tup AS rows_to_delete_before_auto_vacuum,
    last_autovacuum,
        last_vacuum,
        last_analyze
FROM (
    SELECT
        schemaname,
        relname,
        autovacuum_vacuum_scale_factor,
        autovacuum_vacuum_threshold,
        autovacuum_analyze_scale_factor,
        autovacuum_analyze_threshold,
        floor(autovacuum_analyze_scale_factor::numeric * reltuples) + autovacuum_analyze_threshold::int AS autovacuum_analyze_trigger,
        floor(autovacuum_vacuum_scale_factor::numeric * reltuples)  + autovacuum_vacuum_threshold::int AS autovacuum_vacuum_trigger,
        reltuples,
        n_live_tup,
        n_dead_tup,
        n_mod_since_analyze,
        last_autoanalyze,
        last_autovacuum,
        last_vacuum,
        last_analyze
    FROM
        v,
        t) a;
