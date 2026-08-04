-- File Name: table_by_sqlid.sql
-- Purpose: YashanDB Show tables referenced by a sql_id (objects from v$sql_plan)
-- Created: 20260731  by  huangtingzhong
--
-- Usage: ytop/yasql -f table_by_sqlid.sql   (prompt for sql_id)
-- Notes:
--   Drive from the small v$sql_plan object set, then join dictionary views.
--   Avoid (owner,table_name) IN (UNION ...) against DBA_TABLES (full scan +
--   semi-join explosion on YashanDB). MATERIALIZE hint is not supported.

col owner              for a15
col table_name         for a25
col l_t                for a5
col degree             for a6
col part               for a4
col LAST_ANALYZED      for a19
col NUM_ROWS           for a10
col blocks             for a10
col EMPTY_BLOCKS       for a5
col AVG_SPACE          for a9
col AVG_ROW_LEN        for a10
col block_size         for a10
col avg_size           for a10
col STALE_STATS        for a6

prompt ****************************************************************************************
prompt TABLES referenced by sql_id = &&sqlid   (from v$sql_plan objects)
prompt ****************************************************************************************

WITH t AS (
  SELECT DISTINCT object_owner AS owner, object_name AS name
    FROM v$sql_plan
   WHERE sql_id = '&&sqlid'
     AND object_name IS NOT NULL
),
tbl AS (
  /* index object -> underlying table */
  SELECT DISTINCT i.table_owner AS owner, i.table_name
    FROM t
    JOIN dba_indexes i
      ON i.owner = t.owner
     AND i.index_name = t.name
  UNION
  /* table / fixed-table name that exists in dba_tables */
  SELECT t.owner, t.name
    FROM t
    JOIN dba_tables dt
      ON dt.owner = t.owner
     AND dt.table_name = t.name
)
SELECT a.owner,
       a.table_name,
       a.logging || '.' || a.temporary AS l_t,
       LTRIM(a.degree) AS degree,
       a.partitioned AS part,
       a.num_rows || '' AS num_rows,
       a.blocks || '' AS blocks,
       a.empty_blocks || '' AS empty_blocks,
       b.avg_space || '' AS avg_space,
       b.avg_row_len || '' AS avg_row_len,
       TRUNC((b.blocks * tp.block_size) / 1024 / 1024) || '' AS block_size,
       TRUNC((b.avg_row_len * b.num_rows) / 1024 / 1024) || '' AS avg_size,
       b.stale_stats,
       TO_CHAR(a.last_analyzed, 'yyyy-mm-dd hh24:mi:ss') AS last_analyzed
  FROM tbl x
  JOIN dba_tables a
    ON a.owner = x.owner
   AND a.table_name = x.table_name
  LEFT JOIN dba_tab_statistics b
    ON b.owner = a.owner
   AND b.table_name = a.table_name
   AND b.object_type = 'TABLE'
  LEFT JOIN dba_tablespaces tp
    ON tp.tablespace_name = a.tablespace_name
 ORDER BY a.owner, a.table_name;
