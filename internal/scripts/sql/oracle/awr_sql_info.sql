-- File Name: awr_sql_info.sql
-- Purpose: Oracle AWR SQL Info
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

col BEGIN_INTERVAL_TIME for a23
col PLAN_HASH_VALUE for 9999999999
col date_time for a30
col snap_id heading 'SnapId'
col executions_delta heading "No. of exec"
col sql_profile heading "SQL|Profile" for a7
col date_time heading 'Date time'

col avg_lio heading 'LIO/exec' for 99999999999.99
col avg_cputime heading 'CPUTIM/exec' for 9999999.99
col avg_etime heading 'ETIME/exec' for 9999999.99
col avg_pio heading 'PIO/exec' for 9999999.99
col avg_row heading 'ROWs/exec' for 9999999.99


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display sql info in awr                                                |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

@@awr_snapshot_info.sql
ACCEPT sqlid prompt 'Enter Search Sql_Id (i.e. 12345ddd) : '
ACCEPT begin_snap_id prompt 'Enter Search Begin Snap_Id (i.e. 12345) : '
variable sqlid varchar2(30);
variable begin_snap_id number;
begin
   :sqlid          := '&sqlid';
   :begin_snap_id  := &begin_snap_id;
end;
/
set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

col BEGIN_INTERVAL_TIME for a23
col PLAN_HASH_VALUE for 9999999999
col date_time for a30
col snap_id heading 'SnapId'
col executions_delta heading "No. of exec"
col sql_profile heading "SQL|Profile" for a7
col date_time heading 'Date time'

col avg_lio heading 'LIO/exec' for 99999999999.99
col avg_cputime heading 'CPUTIM/exec' for 9999999.99
col avg_etime heading 'ETIME/exec' for 9999999.99
col avg_pio heading 'PIO/exec' for 9999999.99
col avg_row heading 'ROWs/exec' for 9999999.99
/* Formatted on 2012/11/22 17:45:24 (QP5 v5.215.12089.38647) */
  SELECT DISTINCT
         s.snap_id,
         PLAN_HASH_VALUE,
            TO_CHAR (s.BEGIN_INTERVAL_TIME, 'yyyy-mm-dd_hh24:mi')
         || TO_CHAR (s.END_INTERVAL_TIME, '_hh24:mi')
            Date_Time,
         SQL.executions_delta,
           SQL.buffer_gets_delta
         / DECODE (NVL (SQL.executions_delta, 0), 0, 1, SQL.executions_delta)
            avg_lio,
           --SQL.ccwait_delta,
           (SQL.cpu_time_delta / 1000000)
         / DECODE (NVL (SQL.executions_delta, 0), 0, 1, SQL.executions_delta)
            avg_cputime,
           (SQL.elapsed_time_delta / 1000000)
         / DECODE (NVL (SQL.executions_delta, 0), 0, 1, SQL.executions_delta)
            avg_etime,
           SQL.DISK_READS_DELTA
         / DECODE (NVL (SQL.executions_delta, 0), 0, 1, SQL.executions_delta)
            avg_pio,
           SQL.rows_processed_total
         / DECODE (NVL (SQL.executions_delta, 0), 0, 1, SQL.executions_delta)
            avg_row
    --,SQL.sql_profile
    FROM dba_hist_sqlstat SQL, dba_hist_snapshot s
   WHERE     SQL.instance_number = (SELECT instance_number FROM v$instance)
         AND SQL.dbid = (SELECT dbid FROM v$database)
         AND s.snap_id = SQL.snap_id
         AND sql_id =decode(upper(:sqlid),'ALL',sql_id,:sqlid)
		 AND s.snap_id > :begin_snap_id
ORDER BY s.snap_id
/
clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

