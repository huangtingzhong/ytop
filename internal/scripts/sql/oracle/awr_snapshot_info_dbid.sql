-- File Name: awr_snapshot_info_dbid.sql
-- Purpose: Oracle AWR Snapshot Info Dbid
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off  feedback off lines 250 pages 50 heading on

column instart_fmt noprint;
column inst_name   format a12  heading 'Instance';
column db_name     format a12  heading 'DB Name';
column snap_id     format 99999990 heading 'Snap Id';
column snapdat     format a19  heading 'Snap Started' just c;
column lvl         format 99   heading 'Snap|Level';
column dbid        format 99999999999999 
column name        format a10 heading 'DB NAME'
column instance_number for 99 heading 'I'
column min_start_time for a21
column max_start_time for a21
column min_begin_time for a21
column max_begin_time for a21

select distinct a.dbid,
                b.instance_name inst_name,
                a.instance_number,
                to_char(min(a.startup_time), 'yyyy-mm-dd hh24:mi:ss') max_start_time,
                to_char(max(a.startup_time), 'yyyy-mm-dd hh24:mi:ss') min_start_time,
                to_char(min(a.begin_interval_time), 'yyyy-mm-dd hh24:mi:ss') min_begin_time,
                to_char(max(a.begin_interval_time), 'yyyy-mm-dd hh24:mi:ss') max_begin_time
  from dba_hist_snapshot a, dba_hist_database_instance b
 where a.dbid = b.dbid
   and a.instance_number = b.instance_number
 group by a.dbid, b.instance_name, a.instance_number
 order by a.dbid, a.instance_number
/

ACCEPT dbid prompt 'Enter Search dbid (i.e. 613767994) : '
ACCEPT begin_date prompt 'Enter Search Snapshot Begin date (2015-12-15 24:00:00) : '
ACCEPT instance_number prompt 'Enter Search Instance Number  (i.e. 1(default)) : ' default '1'

variable begin_date  varchar2(20);
variable dbid number;
variable instance_num number;

begin
  :begin_date  :=  '&begin_date';
  :dbid := &&dbid;
  :instance_num := &&instance_number;
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
   WHERE     s.instance_number = di.instance_number 
         and s.instance_number = :instance_num
         AND di.dbid = s.dbid
         AND di.dbid = :dbid
         AND di.startup_time = s.startup_time
         AND s.end_interval_time >= to_date(:begin_date,'yyyy-mm-dd hh24:mi:ss')
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

