-- File Name: table_last_xid.sql
-- Purpose: PostgreSQL Table Last Xid
-- Created: 20260516  by  huangtingzhong

SELECT 
  n.nspname || '.' || c.relname AS table_name,
  age(c.relfrozenxid) AS xid_age,
  current_setting('autovacuum_freeze_max_age')::int AS freeze_max_age,
  round(100.0 * age(c.relfrozenxid) / current_setting('autovacuum_freeze_max_age')::int, 2) AS percent_to_wraparound,
  c.reltuples::bigint AS estimated_rows
FROM 
  pg_class c
JOIN 
  pg_namespace n ON n.oid = c.relnamespace
WHERE 
  c.relkind = 'r' -- regular tables only
ORDER BY 
  age(c.relfrozenxid) DESC
LIMIT 20;
