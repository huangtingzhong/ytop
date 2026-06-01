-- File Name: log_size.sql
-- Purpose: Oracle Log Size
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 100
break on inst_id on group#
col f_time for a19 heading 'First Time'
col inst_id for 9999 heading 'inst|id'
col status for a10
col type for a10
col member for a40
col bytes for 9999999 heading 'bytes|M'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display logfile and member info                                        |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

/* Formatted on 2012-11-6 13:59:59 (QP5 v5.185.11230.41888) */
SELECT a.inst_id,
       a.group#,
       b.status,
       a.TYPE,
       round(bytes/1024/1024) bytes,
       a.status,
       a.MEMBER,
       TO_CHAR (first_time, 'yyyymmdd hh24:mi:ss') f_time
  FROM gv$logfile a, gv$log b
 WHERE a.inst_id = b.inst_id AND a.group# = b.group#
UNION ALL
SELECT a.inst_id,
       a.group#,
       b.status,
       a.TYPE,
       bytes / 1024 / 1024,
       a.status,
       a.MEMBER,
       TO_CHAR (first_time, 'yyyymmdd hh24:mi:ss')
  FROM gv$logfile a, gv$standby_log b
 WHERE a.inst_id = b.inst_id AND a.group# = b.group#
ORDER BY inst_id, group#
/
clear    breaks  
set lines 80
set pages 5
set echo on
set verify on