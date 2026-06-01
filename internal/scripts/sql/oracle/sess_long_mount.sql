-- File Name: sess_long_mount.sql
-- Purpose: Oracle session Long Mount
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off heading on pages 100
set serveroutput on
set feedback off
set lines 200
col sid for 9999999999
col command for  a15
col opname for a30
col seq for 999999999
col target for a20 heading 'OPT_OBJECT'
col sofar for 9999999999999
col totalwork for 999999999999
col time for a28
col units for a10
col time_remaining for 9999999999 heading 'TIME|REMAINING'
col elapsed_seconds for 9999999999 heading 'ELAPSED|SECONDS'
SELECT a.sid,
       a.opname,
       b.seq#,
       a.target,
       a.sofar,
       a.totalwork,
       a.units,
          TO_CHAR (a.start_time, 'yyyy-mm-dd hh24:mi:ss')
       || '-'
       || TO_CHAR (last_update_time, 'hh24:mi:ss')
          time,
       a.time_remaining,
       a.elapsed_seconds
  FROM v$session_longops a, v$session b
 WHERE sofar <> totalwork AND a.sid = b.sid
/
