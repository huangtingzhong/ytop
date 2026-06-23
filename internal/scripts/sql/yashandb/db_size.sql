-- File Name: db_size.sql
-- Purpose: YashanDB tablespace — usage vs autoextend capacity (hypothetical)
-- Created: 20251208  by  huangtingzhong
-- Note: Max_MB / %U_Auto / RemAuto answer: "if datafiles use autoextend, how full am I?"
--       Per-file auto cap: MAXBYTES when AUTOEXTEND ON; else platform default
--       (512G for PERMANENT/TEMP/SWAP, 64G for UNDO — yasboot DATA_FILE_MAX_SIZE).
--       A/N column: A(autoextend file count) N(non-autoextend file count) per tablespace.

col Tablespace for a16
col "A/N" for a10
col Size_MB for a8
col Free_MB for a8
col Max_MB for a8
col RemAuto for a8
col "% Used" for a7
col "%U_Auto" for a7

WITH df AS (
  SELECT f.tablespace_name,
         SUM(f.bytes) AS bytes,
         SUM(CASE
               WHEN f.autoextensible = 'YES' THEN f.maxbytes
               WHEN t.contents = 'UNDO' THEN 65536 * 1024 * 1024
               ELSE 524288 * 1024 * 1024
             END) AS auto_cap_bytes
    FROM dba_data_files f
    JOIN dba_tablespaces t ON t.tablespace_name = f.tablespace_name
   GROUP BY f.tablespace_name
),
fc AS (
  SELECT tablespace_name,
         SUM(CASE WHEN autoextensible = 'YES' THEN 1 ELSE 0 END) AS auto_cnt,
         SUM(CASE WHEN autoextensible = 'NO'  THEN 1 ELSE 0 END) AS noauto_cnt
    FROM dba_data_files
   GROUP BY tablespace_name
),
fs AS (
  SELECT tablespace_name,
         SUM(bytes) AS free_bytes
    FROM dba_free_space
   GROUP BY tablespace_name
),
calc AS (
  SELECT df.tablespace_name,
         df.bytes,
         df.auto_cap_bytes,
         NVL(fs.free_bytes, 0) AS free_bytes,
         df.bytes - NVL(fs.free_bytes, 0) AS used_bytes,
         NVL(fc.auto_cnt, 0) AS auto_cnt,
         NVL(fc.noauto_cnt, 0) AS noauto_cnt
    FROM df
    LEFT JOIN fs ON fs.tablespace_name = df.tablespace_name
    LEFT JOIN fc ON fc.tablespace_name = df.tablespace_name
)
SELECT c.tablespace_name AS "Tablespace",
       'A(' || c.auto_cnt || ')N(' || c.noauto_cnt || ')' AS "A/N",
       TO_CHAR(ROUND(c.bytes / (1024 * 1024))) AS "Size_MB",
       TO_CHAR(ROUND(c.free_bytes / (1024 * 1024))) AS "Free_MB",
       TO_CHAR(ROUND(c.auto_cap_bytes / (1024 * 1024))) AS "Max_MB",
       TO_CHAR(ROUND((c.auto_cap_bytes - c.used_bytes) / (1024 * 1024))) AS "RemAuto",
       TO_CHAR(ROUND(c.used_bytes * 100 / NULLIF(c.bytes, 0))) AS "% Used",
       TO_CHAR(ROUND(c.used_bytes * 100 / NULLIF(c.auto_cap_bytes, 0), 1)) AS "%U_Auto"
  FROM calc c
 ORDER BY c.tablespace_name;
