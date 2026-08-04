-- File Name: index_by_sqlid.sql
-- Purpose: YashanDB Show indexes on tables referenced by a sql_id
-- Created: 20260731  by  huangtingzhong
--
-- Usage: ytop/yasql -f index_by_sqlid.sql   (prompt for sql_id)
-- Notes: Drive from small v$sql_plan object set (same pattern as table_by_sqlid.sql).
--        ucptv = Uniqueness/Compression/Partitioned/Temporary/Visibility flags.

col table_owner        for a15
col table_name         for a25
col index_name         for a64
col ucptv              for a6
col column_name        for a28
col column_position    for a8
col descend            for a7

prompt ****************************************************************************************
prompt INDEXES on tables referenced by sql_id = &&sqlid
prompt (ucptv = Uniqueness Compression Partitioned Temporary Visibility)
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
SELECT a.table_owner,
       a.table_name,
       a.index_name,
          DECODE(a.uniqueness,  'UNIQUE', 'U',  'NONUNIQUE', 'N',  'O')
       || DECODE(a.compression, 'ENABLED','E',  'DISABLED',  'N',  'O')
       || DECODE(a.partitioned,'YES',    'Y',  'NO',        'N',  'O')
       || DECODE(a.temporary,  'Y',      'Y',  'N',         'N',  'O')
       || DECODE(a.visibility, 'VISIBLE','V',  'INVISIBLE', 'I',  'O') AS ucptv,
       b.column_name,
       b.column_position || '' AS column_position,
       b.descend
  FROM tbl x
  JOIN dba_indexes a
    ON a.table_owner = x.owner
   AND a.table_name = x.table_name
  JOIN dba_ind_columns b
    ON a.owner = b.index_owner
   AND a.index_name = b.index_name
 ORDER BY a.table_owner, a.table_name, a.index_name, b.column_position;
