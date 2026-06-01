-- File Name: awr_sysstat_redo_size.sql
-- Purpose: Oracle AWR Sysstat Redo Size
-- Created: 20260516  by  huangtingzhong

set serveroutput on
set lines 200
set pages 100
set echo off
col t_date heading 'SNAP_END_TIME'
col t_size heading 'SIZE(M)'
ACCEPT bid prompt 'Enter Search Begin Snap Id (i.e. 2)) : ' 
ACCEPT eid prompt 'Enter Search End Snap Id (i.e. 4)) : '  
  SELECT a.instance_number,b.snap_id,
         TO_CHAR (b.end_interval_time, 'yyyy-mm-dd hh24:mi:ss') t_date,
         stat_name,
         ROUND (VALUE / 1024 / 1024, 2) t_size
    FROM dba_hist_sysstat a, dba_hist_snapshot b
   WHERE     a.snap_id = B.SNAP_ID
         AND a.instance_number = b.instance_number
         AND a.stat_name = 'redo size'
                  AND a.instance_number=nvl('&inst_num',a.instance_number)
ORDER BY snap_id,instance_number;