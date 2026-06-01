-- File Name: awr_tablespace_size_trend_by_day.sql
-- Purpose: Oracle AWR Tablespace Size Trend By Day
-- Created: 20260516  by  huangtingzhong

set echo off
set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 1000

col snap_id for 99999999
col name for a20 heading 'TABLESPACE_NAME'
col ts_size_mb for 9999999 heading 'TB_SIZE(M)'
col ts_used_mb for 9999999 heading 'TB_USED(M)'
col ts_free_mb for 9999999 heading 'TB_FREE(M)'
col differ for 999999 heading 'DIFFER(M)'
break on NAME skip 1
  SELECT 
         a.name,
         a.end_day,
         a.ts_size_mb,
         a.ts_used_mb,
         ROUND (a.ts_used_mb / a.ts_size_mb * 100) pct_used,
         (a.ts_size_mb - a.ts_used_mb) ts_free_mb,
           (a.ts_size_mb - a.ts_used_mb)
         - nvl((LAG ( (a.ts_size_mb - a.ts_used_mb))
               OVER (PARTITION BY a.name ORDER BY end_day)),(a.ts_size_mb - a.ts_used_mb))
            free_sine_last,
           a.ts_used_mb
         - nvl(LAG (a.ts_used_mb)
               OVER (PARTITION BY a.name ORDER BY end_day),a.ts_used_mb)
            used_sine_last
    FROM (  SELECT TO_CHAR (s.end_interval_time, 'yyyy-mm-dd') end_day,
                   t.name,
                   ROUND (MAX (u.tablespace_size * ts.block_size) / 1024 / 1024,
                          2)
                      ts_size_mb,
                   ROUND (
                      MAX (u.tablespace_usedsize * ts.block_size) / 1024 / 1024,
                      2)
                      ts_used_mb
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
          GROUP BY TO_CHAR (s.end_interval_time, 'yyyy-mm-dd'), t.name) a
ORDER BY name,end_day
/
clear    breaks  
