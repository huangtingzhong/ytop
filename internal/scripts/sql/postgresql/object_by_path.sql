-- File Name: object_by_path.sql
-- Purpose: PostgreSQL Object By Path
-- Created: 20260516  by  huangtingzhong

\prompt 'please input object file node(1663/14213/1249): '  path
WITH input AS (
    SELECT :'path' AS path_str
),
parsed AS (
    SELECT
        split_part(path_str, '/', 1)::oid AS spc_oid,
        split_part(path_str, '/', 2)::oid AS db_oid,
        split_part(path_str, '/', 3)::oid AS relfilenode
    FROM input
)
SELECT
    sp.spcname AS tablespace_name,
    db.datname AS database_name,
    n.nspname || '.' || c.relname AS object_name
FROM parsed p
LEFT JOIN pg_tablespace sp
       ON sp.oid = p.spc_oid
LEFT JOIN pg_database db
       ON db.oid = p.db_oid
LEFT JOIN pg_class c
       ON c.relfilenode = p.relfilenode
      AND (c.reltablespace = 0 OR c.reltablespace = p.spc_oid)
LEFT JOIN pg_namespace n
       ON n.oid = c.relnamespace;
