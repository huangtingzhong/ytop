-- File Name: awr_tablespace_size_trend_by_hour.sql
-- Purpose: Oracle AWR Tablespace Size Trend By Hour
-- Created: 20260516  by  huangtingzhong

set echo off
store set sqlplusset replace
set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 40

col snap_id for 99999999
col name for a20 heading 'TABLESPACE_NAME'
col ts_size_mb for 9999999 heading 'TB_SIZE(M)'
col ts_used_mb for 9999999 heading 'TB_USED(M)'
col ts_free_mb for 9999999 heading 'TB_FREE(M)'
col differ for 999999 heading 'DIFFER(M)'
break on  snap_id skip 1

   SELECT  u.snap_id,
         TO_CHAR (s.end_interval_time, 'yyyy-mm-dd hh24') end_time,
          t.name,      
         ROUND (u.tablespace_size * ts.block_size / 1024 / 1024, 2) ts_size_mb,
         ROUND (u.tablespace_usedsize * ts.block_size / 1024 / 1024, 2)
            ts_used_mb,
         ROUND (u.tablespace_usedsize / u.tablespace_size * 100, 2) pct_used,
         ROUND (
              (u.tablespace_size - u.tablespace_usedsize)
            * ts.block_size
            / 1024
            / 1024,
            2)
            ts_free_mb,
         ROUND (
              (  (u.tablespace_size - u.tablespace_usedsize)
               - LAG (
                    ( (u.tablespace_size - u.tablespace_usedsize)),
                    1,
                    0)
                 OVER (
                    PARTITION BY t.name
                    ORDER BY TO_CHAR (s.end_interval_time, 'yyyy-mm-dd hh24')))
            * ts.block_size
            / 1024
            / 1024,
            2)
            differ
    FROM dba_hist_tbspc_space_usage u,
         v$tablespace t,
         dba_hist_snapshot s,
         dba_tablespaces ts
   WHERE     u.tablespace_id = t.ts#
         AND u.snap_id = s.snap_id
         AND t.name = ts.tablespace_name
         AND s.instance_number = 1
         AND t.name = NVL (UPPER ('&tablespace_name'), t.name)
         AND s.end_interval_time > SYSDATE - 7
ORDER BY u.snap_id,name;
clear    breaks  
undefine tablespace_name