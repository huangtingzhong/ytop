-- File Name: datafile.sql
-- Purpose: YashanDB Show datafile and tablespace usage
-- Created: 20260516  by  huangtingzhong

-- Params: &&tablespace_name, &&file_id (empty means no filter).
-- Unset vars mean no filter to avoid TO_NUMBER on literal &&file_id.

SELECT a.tablespace_name,
       a.file_name,
       a.file_id,
       NULL AS relative_fno,
       SUBSTR(a.status, 1, 10) AS status,
       a.autoextensible,
       TRUNC(a.bytes / 1024 / 1024) AS bytes,
       TRUNC(a.maxbytes / 1024 / 1024) AS maxbytes
  FROM dba_data_files a
 WHERE a.tablespace_name = NVL('&&tablespace_name',a.tablespace_name)
   AND  a.file_id = NVL('&&file_id', a.file_id)
UNION ALL
SELECT a.tablespace_name,
       a.file_name,
       a.file_id,
       a.relative_fno,
       SUBSTR(a.status, 1, 10) AS status,
       a.autoextensible,
       TRUNC(a.bytes / 1024 / 1024) AS bytes,
       TRUNC(a.maxbytes / 1024 / 1024) AS maxbytes
  FROM dba_temp_files a
 WHERE a.tablespace_name = NVL('&&tablespace_name',a.tablespace_name)
   AND a.file_id = NVL('&&file_id', a.file_id)
 ORDER BY 1, 3;
