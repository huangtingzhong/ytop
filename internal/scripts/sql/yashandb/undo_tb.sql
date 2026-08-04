-- File Name: undo_tb.sql
-- Purpose: UNDO tablespace files, segment usage and undostat pressure summary
-- Created: 20260801 by huangtingzhong
-- Oracle ref: /Users/yihan/Documents/owner/sql/undo_tb.sql
-- Note: used_mb from v$undo_segments.ublk_count * DB_BLOCK_SIZE (not Oracle extent status)

col name       for a24
col value      for a20
col tbs        for a16
col file_id    for a8
col size_mb    for a10
col max_mb     for a10
col autoext    for a5
col status     for a10
col file_name  for a60

PROMPT ===== UNDO parameters =====
SELECT name, value
  FROM v$parameter
 WHERE name IN ('UNDO_RETENTION', 'UNDO_SHRINK_ENABLED', 'UNDO_SHRINK_INTERVAL', 'DB_BLOCK_SIZE')
 ORDER BY name;

PROMPT ===== UNDO data files =====
SELECT f.tablespace_name AS tbs,
       TO_CHAR(f.file_id) AS file_id,
       TO_CHAR(ROUND(f.bytes / 1024 / 1024)) AS size_mb,
       TO_CHAR(ROUND(f.maxbytes / 1024 / 1024)) AS max_mb,
       f.autoextensible AS autoext,
       f.status,
       SUBSTR(f.file_name, 1, 60) AS file_name
  FROM dba_data_files f
 WHERE f.tablespace_name IN (
         SELECT tablespace_name FROM dba_tablespaces WHERE contents = 'UNDO'
       )
 ORDER BY f.tablespace_name, f.file_id;

col segs       for a6
col ublk       for a12
col used_mb    for a10
col file_mb    for a10
col used_pct   for a8
col surplus    for a12
col free_cnt   for a10
col ufb_cnt    for a10

PROMPT ===== UNDO usage (ublk_count * DB_BLOCK_SIZE vs file size) =====
SELECT TO_CHAR(s.segs) AS segs,
       TO_CHAR(s.ublk) AS ublk,
       TO_CHAR(ROUND(s.ublk * b.bs / 1024 / 1024, 2)) AS used_mb,
       TO_CHAR(ROUND(f.file_bytes / 1024 / 1024)) AS file_mb,
       TO_CHAR(
         CASE
           WHEN f.file_bytes = 0 THEN NULL
           ELSE ROUND(100 * s.ublk * b.bs / f.file_bytes, 1)
         END
       ) AS used_pct,
       TO_CHAR(s.surplus) AS surplus,
       TO_CHAR(s.free_cnt) AS free_cnt,
       TO_CHAR(s.ufb_cnt) AS ufb_cnt
  FROM (
        SELECT COUNT(*) AS segs,
               NVL(SUM(ublk_count), 0) AS ublk,
               NVL(SUM(surplus_count), 0) AS surplus,
               NVL(SUM(free_count), 0) AS free_cnt,
               NVL(SUM(ufb_count), 0) AS ufb_cnt
          FROM v$undo_segments
       ) s,
       (
        SELECT NVL(SUM(bytes), 0) AS file_bytes
          FROM dba_data_files
         WHERE tablespace_name IN (
                 SELECT tablespace_name FROM dba_tablespaces WHERE contents = 'UNDO'
               )
       ) f,
       (
        SELECT CASE
                 WHEN UPPER(value) = '8K' THEN 8192
                 WHEN UPPER(value) = '16K' THEN 16384
                 WHEN UPPER(value) = '32K' THEN 32768
                 ELSE TO_NUMBER(value)
               END AS bs
          FROM v$parameter
         WHERE name = 'DB_BLOCK_SIZE'
       ) b;

col seg_id     for a8
col used_time  for a19
col ublk_cnt   for a10
col surplus    for a10
col free_cnt   for a8
col ufb_cnt    for a8
col xblks      for a8

PROMPT ===== TOP undo segments by ublk_count =====
SELECT TO_CHAR(id) AS seg_id,
       TO_CHAR(used_time, 'yyyy-mm-dd hh24:mi:ss') AS used_time,
       TO_CHAR(ublk_count) AS ublk_cnt,
       TO_CHAR(surplus_count) AS surplus,
       TO_CHAR(free_count) AS free_cnt,
       TO_CHAR(ufb_count) AS ufb_cnt,
       TO_CHAR(xblks) AS xblks
  FROM v$undo_segments
 ORDER BY ublk_count DESC NULLS LAST, id
 FETCH FIRST 20 ROWS ONLY;

col steal      for a10
col stealed    for a10
col blk_reuse  for a10
col blk_append for a12
col blk_alloc  for a10
col avg_xact   for a12

PROMPT ===== UNDOSTAT pressure summary =====
SELECT TO_CHAR(SUM(steal)) AS steal,
       TO_CHAR(SUM(stealed)) AS stealed,
       TO_CHAR(SUM(blk_reuse)) AS blk_reuse,
       TO_CHAR(SUM(blk_append)) AS blk_append,
       TO_CHAR(SUM(blk_alloc)) AS blk_alloc,
       TO_CHAR(ROUND(AVG(xact_avg_size), 2)) AS avg_xact
  FROM v$undostat;
