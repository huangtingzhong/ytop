-- File Name: log_file.sql
-- Purpose: Oracle Log File
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off heading on 
set lines 200
set pages 100
break on inst_id on group#
col f_time for a19 heading 'First Time'
col inst_id for 99 heading 'I'
col status for a10
col type for a10
col member for a60
col group# for 99 heading 'G'
col thread# for 9 heading 'T'
col bytes for 9999999 heading 'bytes|M'
/* Formatted on 2012-11-6 13:59:59 (QP5 v5.185.11230.41888) */
SELECT
       a.group#,
       b.thread#,
       b.status,
       a.TYPE,
       round(bytes/1024/1024) bytes,
       a.status,
       b.FIRST_CHANGE#,
       b.NEXT_CHANGE#,
       a.MEMBER,
       TO_CHAR (first_time, 'yyyymmdd hh24:mi:ss') f_time
  FROM v$logfile a, v$log b
 WHERE a.group# = b.group#
UNION ALL
SELECT 
       a.group#,
       b.thread#,
       b.status,
       a.TYPE,
       bytes / 1024 / 1024,
       a.status,
       b.FIRST_CHANGE#,
       b.NEXT_CHANGE#,
       a.MEMBER,
       TO_CHAR (first_time, 'yyyymmdd hh24:mi:ss')
  FROM v$logfile a, v$standby_log b
 WHERE  a.group# = b.group#
ORDER BY thread#,group#
/
clear    breaks  
