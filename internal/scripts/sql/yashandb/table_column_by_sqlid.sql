-- File Name: table_column_by_sqlid.sql
-- Purpose: YashanDB Show columns of tables referenced by a sql_id
-- Created: 20260731  by  huangtingzhong
--
-- Usage: ytop/yasql -f table_column_by_sqlid.sql   (prompt for sql_id)
-- Notes: Drive from small v$sql_plan object set (same pattern as table_by_sqlid.sql).

col owner              for a15
col table_name         for a25
col COLUMN_NAME        for a25
col d_type             for a22
col NUM_DISTINCT       for a11
col N                  for a2
col NUM_NULLS          for a9
col DENSITY            for a10
col NUM_BUCKETS        for a10
col AVG_COL_LEN        for a10
col sample_size        for a10
col HISTOGRAM          for a10
col LAST_ANALYZED      for a19

prompt ****************************************************************************************
prompt TABLE COLUMNS of tables referenced by sql_id = &&sqlid
prompt ****************************************************************************************

WITH t AS (
  SELECT DISTINCT object_owner AS owner, object_name AS name
    FROM v$sql_plan
   WHERE sql_id = '&&sqlid'
     AND object_name IS NOT NULL
),
tbl AS (
  SELECT DISTINCT i.table_owner AS owner, i.table_name
    FROM t
    JOIN dba_indexes i
      ON i.owner = t.owner
     AND i.index_name = t.name
  UNION
  SELECT t.owner, t.name
    FROM t
    JOIN dba_tables dt
      ON dt.owner = t.owner
     AND dt.table_name = t.name
)
SELECT a.owner,
       a.table_name,
       a.column_name,
       a.data_type || '(' || a.data_length || ')' AS d_type,
       b.num_distinct || '' AS num_distinct,
       a.nullable || '' AS n,
       b.num_nulls || '' AS num_nulls,
       b.density || '' AS density,
       b.num_buckets || '' AS num_buckets,
       b.avg_col_len || '' AS avg_col_len,
       b.sample_size || '' AS sample_size,
       SUBSTR(b.histogram, 1, 5) AS histogram,
       TO_CHAR(b.last_analyzed, 'yyyy-mm-dd hh24:mi:ss') AS last_analyzed
  FROM tbl x
  JOIN dba_tab_cols a
    ON a.owner = x.owner
   AND a.table_name = x.table_name
  LEFT JOIN dba_tab_col_statistics b
    ON b.owner = a.owner
   AND b.table_name = a.table_name
   AND b.column_name = a.column_name
 ORDER BY a.owner, a.table_name, a.column_id;
