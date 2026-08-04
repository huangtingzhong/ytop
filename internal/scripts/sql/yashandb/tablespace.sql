-- File Name: tablespace.sql
-- Purpose: Show tablespace size free used percent (incl TEMP/SWAP files)
-- Created: 20260801 by huangtingzhong
-- Note: For autoextend capacity detail see db_size.sql

col tablespace_name for a16
col status          for a10
col contents        for a10
col size_mb         for a10
col free_mb         for a10
col used_mb         for a10
col used_pct        for a8

SELECT t.tablespace_name,
       t.status,
       t.contents,
       TO_CHAR(ROUND(NVL(df.bytes, NVL(tf.bytes, 0)) / 1024 / 1024)) AS size_mb,
       TO_CHAR(ROUND(NVL(fs.free_bytes, NVL(tfs.free_space, 0)) / 1024 / 1024)) AS free_mb,
       TO_CHAR(
         ROUND(
           (NVL(df.bytes, NVL(tf.bytes, 0)) - NVL(fs.free_bytes, NVL(tfs.free_space, 0)))
           / 1024 / 1024
         )
       ) AS used_mb,
       TO_CHAR(
         CASE
           WHEN NVL(df.bytes, NVL(tf.bytes, 0)) = 0 THEN NULL
           ELSE ROUND(
                  100
                  * (NVL(df.bytes, NVL(tf.bytes, 0))
                     - NVL(fs.free_bytes, NVL(tfs.free_space, 0)))
                  / NVL(df.bytes, NVL(tf.bytes, 0)),
                  1
                )
         END
       ) AS used_pct
  FROM dba_tablespaces t
  LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) AS bytes
          FROM dba_data_files
         GROUP BY tablespace_name
       ) df
    ON df.tablespace_name = t.tablespace_name
  LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) AS bytes
          FROM dba_temp_files
         GROUP BY tablespace_name
       ) tf
    ON tf.tablespace_name = t.tablespace_name
  LEFT JOIN (
        SELECT tablespace_name, SUM(bytes) AS free_bytes
          FROM dba_free_space
         GROUP BY tablespace_name
       ) fs
    ON fs.tablespace_name = t.tablespace_name
  LEFT JOIN dba_temp_free_space tfs
    ON tfs.tablespace_name = t.tablespace_name
 ORDER BY t.tablespace_name;
