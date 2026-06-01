-- File Name: object_vacuum.sql
-- Purpose: PostgreSQL Object Vacuum
-- Created: 20260516  by  huangtingzhong

\set scientific off
\prompt 'please input object name: '  name
WITH table_settings AS (
  SELECT
    current_database() AS database_name,
    c.oid,
    n.nspname AS schema_name,
    c.relname AS table_name,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    c.reltuples AS live_tuples,
    pg_stat_get_dead_tuples(c.oid) AS dead_tuples,
    pg_stat_get_tuples_inserted(c.oid) AS n_tup_ins,
    pg_stat_get_tuples_updated(c.oid) AS n_tup_upd,
    pg_stat_get_tuples_deleted(c.oid) AS n_tup_del,

    -- vacuum
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_vacuum_threshold=(\d+)'))[1],
      current_setting('autovacuum_vacuum_threshold')
    )::int AS vacuum_threshold,
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_vacuum_scale_factor=([\d.]+)'))[1],
      current_setting('autovacuum_vacuum_scale_factor')
    )::float AS vacuum_scale_factor,

    -- analyze
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_analyze_threshold=(\d+)'))[1],
      current_setting('autovacuum_analyze_threshold')
    )::int AS analyze_threshold,
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_analyze_scale_factor=([\d.]+)'))[1],
      current_setting('autovacuum_analyze_scale_factor')
    )::float AS analyze_scale_factor,

    -- insert-trigger vacuum（PostgreSQL 13+）
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_vacuum_insert_threshold=(\d+)'))[1],
      current_setting('autovacuum_vacuum_insert_threshold', true)
    )::int AS insert_threshold,
    coalesce(
      (regexp_match(array_to_string(c.reloptions, ','), 'autovacuum_vacuum_insert_scale_factor=([\d.]+)'))[1],
      current_setting('autovacuum_vacuum_insert_scale_factor', true)
    )::float AS insert_scale_factor

  FROM pg_class c
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE c.relkind in ( 'r','m','t') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
),
stats AS (
  SELECT
    relid,
    last_autovacuum,
    last_autoanalyze,
    n_mod_since_analyze
  FROM pg_stat_all_tables
)
SELECT
  t.database_name,
  t.owner,
  t.schema_name,
  t.table_name,
  t.live_tuples,
  t.n_tup_upd,
  t.n_tup_del,
  s.last_autovacuum,
  s.last_autoanalyze,
  -- plain VACUUM trigger
  t.dead_tuples,
  t.vacuum_threshold,
  t.vacuum_scale_factor,
  (t.vacuum_threshold + t.vacuum_scale_factor * t.live_tuples)::int AS vacuum_trigger_threshold,

  -- analyze trigger
  s.n_mod_since_analyze,
  t.analyze_threshold,
  t.analyze_scale_factor,
  (t.analyze_threshold + t.analyze_scale_factor * t.live_tuples)::int AS analyze_trigger_threshold,

  -- insert trigger
  t.n_tup_ins,
  t.insert_threshold,
  t.insert_scale_factor,
  (t.insert_threshold + t.insert_scale_factor * t.live_tuples)::int AS insert_vacuum_trigger_threshold

FROM table_settings t
LEFT JOIN stats s ON t.oid = s.relid
Where t.table_name LIKE '%' || :'name' || '%'
ORDER BY t.database_name, t.owner, t.schema_name, t.table_name;
