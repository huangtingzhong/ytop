-- File Name: sess_event_statistics.sql
-- Purpose: Oracle session Event Statistics
-- Created: 20260516  by  huangtingzhong

set echo off
set echo off
set verify off
set heading on
set serveroutput on
set feedback off
set lines 200
set pages 1000
col sid for 9999999999
col total_waits for 9999999999 heading 'NUMBER|WAIT'
col total_timeouts for 999999999 heading 'NUMBER|TIMEOUTS'
col event for a30
col WAIT_CLASS for a17
/* Formatted on 2013/4/11 16:12:52 (QP5 v5.240.12305.39476) */
  SELECT sid,
         substr(event,1,29) event, 
         wait_class,
         total_waits,
         total_timeouts,
         ROUND (time_waited / 100, 2) time_waited,
         ROUND (average_wait / 100, 2) average_wait,
         ROUND (max_wait / 100, 2) max_wait,
         event_id,
         wait_class_id,
         wait_class#
    FROM v$session_event
   WHERE sid = NVL ('&sid', sid) AND wait_class NOT IN ('Idle')
ORDER BY time_waited DESC

/
clear    breaks  
undefine sid

