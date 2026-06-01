-- File Name: table_column.sql
-- Purpose: PostgreSQL Show table columns and data types
-- Created: 20260516  by  huangtingzhong

col owner        for a15
col table_name   for a25
col column_name  for a35
col d_type       for a20
col nullable     for a8
col last_analyzed for a12


SELECT tb.OWNER,
       tb.TABLE_NAME,
       tb.COLUMN_NAME,
       tb.data_type || '(' || data_length || ')' AS d_type,
       ts.NUM_DISTINCT,
       ts.DENSITY,
       tb.NULLABLE,
       ts.NUM_NULLS,
       ts.AVG_COL_LEN,
       TO_CHAR(ts.LAST_ANALYZED, 'MM-DD HH24:MI') AS last_analyzed
  FROM DBA_TAB_COLS tb
  JOIN DBA_TAB_COL_STATISTICS ts
    ON tb.owner = ts.owner(+)
   AND tb.table_name = ts.table_name(+)
   AND tb.column_name = ts.column_name(+)
 WHERE tb.owner = NVL(UPPER('&owner'), tb.owner)
   AND tb.table_name = NVL(UPPER('&table_name'), tb.table_name)
 ORDER BY owner, table_name, COLUMN_ID;
