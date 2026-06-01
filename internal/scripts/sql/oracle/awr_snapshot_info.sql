-- File Name: awr_snapshot_info.sql
-- Purpose: Oracle AWR Snapshot Info
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 30

column instart_fmt noprint;
column inst_name   format a12  heading 'Instance';
column db_name     format a12  heading 'DB Name';
column snap_id     format 99999990 heading 'Snap Id';
column snapdat     format a19  heading 'Snap Started' just c;
column lvl         format 99   heading 'Snap|Level';

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | List available snapshots                                      |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

ACCEPT num_days prompt 'Enter Search Snapshot Create Days (i.e. 2(default)) : ' default '2'


variable num_days  number;
begin
  :num_days  :=  &num_days;
end;
/

break on inst_name on db_name on host on instart_fmt skip 1;

ttitle off;

/* Formatted on 2012-11-23 10:26:57 (QP5 v5.185.11230.41888) */
  SELECT TO_CHAR (s.startup_time, 'dd Mon "at" HH24:mi:ss') instart_fmt,
         di.instance_name inst_name,
         di.db_name db_name,
         s.snap_id snap_id,
         TO_CHAR (s.end_interval_time, 'yyyy-mm-dd hh24:mi:ss') snapdat,
         s.snap_level lvl
    FROM dba_hist_snapshot s, dba_hist_database_instance di
   WHERE     s.dbid = (SELECT dbid FROM v$database)
         AND di.dbid = (SELECT dbid FROM v$database)
         AND s.instance_number = (SELECT instance_number FROM v$instance)
         AND di.instance_number = (SELECT instance_number FROM v$instance)
         AND di.dbid = s.dbid
         AND di.instance_number = s.instance_number
         AND di.startup_time = s.startup_time
         AND s.end_interval_time >=
                (SELECT MAX (b.end_interval_time) - (:num_days - 1)
                   FROM dba_hist_snapshot b)
ORDER BY db_name, instance_name, snap_id;
clear break;
ttitle off;
clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

