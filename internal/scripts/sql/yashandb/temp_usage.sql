-- File Name: temp_usage.sql
-- Purpose: Show TEMP/SWAP free space and current temp segment usage
-- Created: 20260801 by huangtingzhong

col tablespace_name for a16
col size_mb         for a10
col free_mb         for a10
col used_mb         for a10
col used_pct        for a8

PROMPT ===== TEMP / SWAP free space =====
SELECT tablespace_name,
       TO_CHAR(ROUND(tablespace_size / 1024 / 1024)) AS size_mb,
       TO_CHAR(ROUND(free_space / 1024 / 1024)) AS free_mb,
       TO_CHAR(ROUND((tablespace_size - free_space) / 1024 / 1024)) AS used_mb,
       TO_CHAR(
         CASE
           WHEN tablespace_size = 0 THEN NULL
           ELSE ROUND(100 * (tablespace_size - free_space) / tablespace_size, 1)
         END
       ) AS used_pct
  FROM dba_temp_free_space
 ORDER BY tablespace_name;

col username  for a20
col sid       for a8
col tablespace for a12
col contents  for a10
col segtype   for a12
col blocks    for a10
col extents   for a8
col sql_id    for a15

PROMPT ===== Current temp segment usage (v$tempseg_usage) =====
SELECT username,
       TO_CHAR(sid) AS sid,
       tablespace,
       contents,
       segtype,
       TO_CHAR(blocks) AS blocks,
       TO_CHAR(extents) AS extents,
       sql_id
  FROM v$tempseg_usage
 ORDER BY blocks DESC NULLS LAST, sid;
