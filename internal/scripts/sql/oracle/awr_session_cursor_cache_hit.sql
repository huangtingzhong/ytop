-- File Name: awr_session_cursor_cache_hit.sql
-- Purpose: Oracle AWR Session Cursor Cache Hit
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

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000
col snap_time for a20
col instance_number for 99 heading 'I'
COL SESSION_CURSOR_HIT for 99999999 heading 'SESSION|CURSOR_HIT(%)'

undefine begin_id;
undefine end_id;

with tt as
 (select /*+ */
   a.snap_id,
   b.begin_interval_time,
   a.dbid,
   a.instance_number,
   a.stat_name,
   a.value
    from dba_hist_sysstat a, dba_hist_snapshot b
   where a.snap_id >= &begin_id
     and a.snap_id <= &end_id
     and a.dbid = b.dbid
     and a.instance_number = b.instance_number
     and a.snap_id = b.snap_id
     and a.dbid in (select dbid from v$database)
     and a.stat_name in ('parse count (total)',
                         'session cursor cache hits',
                         'parse count (hard)'))
select to_char(a.begin_interval_time, 'yyyy-mm-dd hh24:mi') SNAP_TIME,
       a.instance_number,
       round((nvl(a.value, 0) / nvl((b.value - c.value), 1)), 2) * 100 session_cursor_hit
  from tt a, tt b, tt c
 where a.snap_id = b.snap_id
   and a.snap_id = c.snap_id
   and a.instance_number = b.instance_number
   and a.instance_number = c.instance_number
   and a.stat_name = 'session cursor cache hits'
   and b.stat_name = 'parse count (total)'
   and c.stat_name = 'parse count (hard)'
 order by snap_time, instance_number
 /

undefine begin_id;
undefine end_id;