-- File Name: awr_info.sql
-- Purpose: Oracle AWR Info
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200
alter session set nls_date_format='yyyy-mm-dd hh24:mi:ss';
col FLUSH_ELAPSED for a20
SELECT snap_id,
       dbid,
       instance_number,
       TO_CHAR (startup_time, 'yyyy-mm-dd hh24:mi:ss') startup_time,
       TO_CHAR (end_interval_time, 'yyyy-mm-dd hh24:mi:ss') end_time,
       flush_elapsed,
       snap_level,
       error_count
  FROM dba_hist_snapshot where end_interval_time>sysdate-3 and dbid=(select dbid from v$database)
  order by snap_id;


