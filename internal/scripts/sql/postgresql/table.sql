-- File Name: table.sql
-- Purpose: PostgreSQL Show table storage and column summary
-- Created: 20260516  by  huangtingzhong

\prompt 'please input table name : '  name
WITH table_info AS (
  SELECT
    c.oid AS table_oid,
    n.nspname AS schema_name,
    c.relname AS table_name,
    TO_CHAR(
      CASE 
        WHEN c.reltuples >= 10000 THEN c.reltuples / 10000.0
        WHEN c.reltuples >= 1000 THEN c.reltuples / 1000.0
        ELSE c.reltuples
      END,
      'FM99999990.00'
    ) || 
    CASE 
      WHEN c.reltuples >= 10000 THEN 'W'
      WHEN c.reltuples >= 1000 THEN 'K'
      ELSE ''
    END AS estimated_rows,
    pg_size_pretty((c.relpages::bigint * 8 * 1024)) AS estimated_size
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relname = :'name'
),
analyze_info AS (
  SELECT
    schemaname,
    relname,
    to_char(last_analyze, 'YYYY-MM-DD HH24:MI:SS') AS last_analyze,
    to_char(last_autoanalyze, 'YYYY-MM-DD HH24:MI:SS') AS last_autoanalyze
  FROM pg_stat_all_tables
  WHERE relname = :'name'
),
column_info AS (
  SELECT
    a.attrelid,
    a.attname AS column_name,
    a.attstattarget,
    a.attnum,
    CASE
      WHEN t.typname = 'numeric' AND a.atttypmod = -1 THEN a.attname || ' (numeric)'
      WHEN t.typname = 'numeric' THEN 
        a.attname || ' (numeric(' ||
        (((a.atttypmod::bigint - 4) >> 16)::int) || ',' ||
        (((a.atttypmod::bigint - 4) & 65535)::int) || '))'
      WHEN t.typname = 'varchar' THEN
        a.attname || ' (' || t.typname || '(' || (a.atttypmod::bigint - 4)::int || '))'
      WHEN t.typname = 'bpchar' THEN
        a.attname || ' (varchar(' || (a.atttypmod::bigint - 4)::int || '))'
      ELSE a.attname || ' (' || t.typname || ')'
    END AS column_desc
  FROM pg_attribute a
  JOIN pg_type t ON a.atttypid = t.oid
  WHERE a.attnum > 0 AND NOT a.attisdropped
),
column_stats AS (
  SELECT
    tablename,
    attname AS column_name,
    null_frac,
   n_distinct,
    most_common_vals,
    most_common_freqs,
    histogram_bounds
  FROM pg_stats
  WHERE tablename = :'name'
)
SELECT 
  ti.schema_name as schema,
  ti.table_name as table,
  ti.estimated_rows as rows,
  ti.estimated_size as size,
  ci.column_desc as column,
  CASE 
    WHEN ci.attstattarget = -1 THEN current_setting('default_statistics_target')::int
    ELSE ci.attstattarget
  END as stattarget,
  ai.last_analyze,
  ai.last_autoanalyze,
  cs.null_frac, 
  cs.n_distinct,
-- cs.most_common_vals,
-- cs.most_common_freqs,
-- cs.histogram_bounds
  cardinality(cs.most_common_vals) as vals,
  cardinality(cs.most_common_freqs) as freqs,
  cardinality(cs.histogram_bounds) as bounds
FROM table_info ti
LEFT JOIN analyze_info ai 
  ON ti.schema_name = ai.schemaname AND ti.table_name = ai.relname
JOIN column_info ci 
  ON ti.table_oid = ci.attrelid
LEFT JOIN column_stats cs 
  ON ci.column_name = cs.column_name
ORDER BY ci.attnum;



WITH table_oid AS (
  SELECT c.oid, n.nspname AS schema_name, c.relname AS table_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relname = :'name'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  LIMIT 1
),
index_info AS (
  SELECT
    i.relname AS index_name,
    idx.indisunique AS is_unique,
    idx.indisprimary AS is_primary,
    pg_size_pretty(pg_relation_size(i.oid)) AS index_size,
    '(' || array_to_string(
      ARRAY(
        SELECT pg_get_indexdef(idx.indexrelid, k + 1, true)
        FROM generate_subscripts(idx.indkey, 1) AS k
        ORDER BY k
      ), ','
    ) || ')' AS index_columns
  FROM pg_index idx
  JOIN pg_class i ON i.oid = idx.indexrelid
  JOIN table_oid t ON idx.indrelid = t.oid
),
index_stats AS (
  SELECT
    i.schemaname,
    i.relname AS tablename,
    i.indexrelname AS indexname,
    i.idx_scan AS scan_count,
    i.idx_tup_read AS tuples_read,
    i.idx_tup_fetch AS tuples_fetched,
    CASE 
      WHEN i.idx_scan > 0 THEN round(100.0 * i.idx_tup_read / i.idx_scan, 2)
      ELSE 0 
    END AS avg_tuples_per_scan,
    t.last_analyze,
    t.last_autoanalyze
  FROM pg_stat_user_indexes i
  LEFT JOIN pg_stat_user_tables t ON i.relid = t.relid
  WHERE i.relname = :'name'
)
SELECT
  t.schema_name,
  t.table_name,
  ii.index_name,
  CASE 
    WHEN ii.is_primary THEN 'PK'
    WHEN ii.is_unique THEN 'UQ'
    ELSE 'IX'
  END AS index_type,
  ii.index_size,
  ii.index_columns AS columns,
  COALESCE(istats.scan_count, 0) AS scans,
  COALESCE(istats.tuples_read, 0) AS reads,
  COALESCE(istats.tuples_fetched, 0) AS fetched,
  COALESCE(istats.avg_tuples_per_scan, 0) AS avg_per_scan,
  COALESCE(to_char(istats.last_analyze, 'YYYY-MM-DD HH24:MI:SS'), 'Never') AS last_analyze,
  COALESCE(to_char(istats.last_autoanalyze, 'YYYY-MM-DD HH24:MI:SS'), 'Never') AS last_autoanalyze
FROM table_oid t
JOIN index_info ii ON true
LEFT JOIN index_stats istats ON ii.index_name = istats.indexname
ORDER BY ii.index_name;
