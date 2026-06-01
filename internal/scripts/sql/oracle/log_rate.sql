-- File Name: log_rate.sql
-- Purpose: Oracle Log Rate
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300 pages 10000 heading on
SELECT 
    THREAD#
,   SEQUENCE#
,   to_char(FIRST_TIME,'yyyy-mm-dd hh24:mi:ss') first_time
,   round(BLOCKS*BLOCK_SIZE/1024/1024)     MB
,   (NEXT_TIME-FIRST_TIME)*86400    SEC
,   round((BLOCKS*BLOCK_SIZE/1024/1024)/((NEXT_TIME-FIRST_TIME)*86400),2) "MB/s"
FROM
    V$archived_log
WHERE
    (
        (NEXT_TIME-FIRST_TIME)*86400!=0
    )
    and dest_id in (select dest_id from v$archive_dest_status where type in ('LOCAL'))
ORDER BY
    FIRST_TIME
;
