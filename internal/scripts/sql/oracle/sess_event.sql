-- File Name: sess_event.sql
-- Purpose: Oracle session Event
-- Created: 20260516  by  huangtingzhong

set echo off 
set heading on
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000
break on sid
col evetn for a30 
col total_waits for 9999999999999
col time_waited for 9999999999999
undefine sid
ACCEPT sid prompt 'Enter Search Sid (i.e. 1234) : ' default ''
select se.sid,
       se.event,
       se.total_waits,
       se.time_waited,
       ROUND(100 * ratio_to_report(se.time_waited) over(), 1) pct_total,
       se.AVERAGE_WAIT,
       se.MAX_WAIT,
       TIME_WAITED_MICRO
  from v$session_event se
 where se.sid = nvl('&sid', se.sid)
 order by se.sid, se.time_waited desc;
clear    breaks  

