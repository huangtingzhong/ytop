-- File Name: index.sql
-- Purpose: YashanDB Show index info by owner / table / index name (generic, not sql_id based)
-- Created: 20260731  by  huangtingzhong
--
-- Usage: ytop/yasql -f index.sql   (交互提示 owner / tablename / indexname，任一留空=不过滤)
-- 三处过滤条件均为可选：都留空=列出全部索引。

col owner              for a15
col table_name         for a25
col index_name         for a30
col tablespace_name    for a15
col status             for a8
col index_type         for a14
col uniqueness         for a9
col pct                for a4
col logging            for a5
col blevel             for a3
col d_keys             for a10
col leaf_blocks        for a10
col num_rows           for a10
col part               for a5
col column_position    for a6
col column_name        for a28

prompt ****************************************************************************************
prompt INDEXES  (owner=&&owner  table=&&tablename  index=&&indexname  留空=不过滤)
prompt ****************************************************************************************

SELECT a.owner,
       a.table_name,
       a.index_name,
       a.Tablespace_Name,
       a.status,
       a.index_type,
       a.uniqueness,
       a.pct_free||'' pct,
       a.logging,
       a.blevel||'' blevel,
       a.distinct_keys||'' d_keys,
       a.leaf_blocks||'' leaf_blocks,
       a.num_rows||'' num_rows,
       a.partitioned part,
       b.Column_Position||'' Column_Position,
       b.Column_Name
  FROM dba_indexes a, dba_ind_columns b
 WHERE a.owner      = nvl(upper('&&owner'),      a.owner)
   AND a.table_name = nvl(upper('&&tablename'),  a.table_name)
   AND a.index_name = nvl(upper('&&indexname'),  a.index_name)
   AND b.index_name  = a.index_name
   AND a.owner       = b.index_owner
   AND a.table_owner = b.index_owner
ORDER BY a.owner, a.table_name, a.index_name, b.Column_Position;
