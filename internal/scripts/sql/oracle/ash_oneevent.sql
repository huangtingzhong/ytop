-- File Name: ash_oneevent.sql
-- Purpose: Oracle ASH Oneevent
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 200
set pages 1000
col time for a19 heading 'sample_time'
col sess_id for a15 heading 'session|serial#'
col sqlid for a18 heading 'sql_id|child_number'
col pn_text for a30 heading 'P1_TEXT:P2_TEXT:P3_TEXT'
col pn for a20 heading 'P1:P2:P3'
col oevent for a30 heading 'Event'
col oprogram for a15 heading 'PROGRAM'
col obj for a15 heading 'waiting|obj#:file#block#'
break on time

ACCEPT b_hours prompt 'Enter Search Hours Ago (i.e. 3) : '
ACCEPT e_hours prompt 'Enter How Many Hours  (i.e. 3) : '
ACCEPT i_event prompt 'Enter Search Event Name   (i.e. db file) : '
variable b_hours number;
variable e_hours number;
variable i_event varchar2(35);
begin
   :e_hours:=&e_hours;
   :b_hours:=&b_hours;
   :i_event:='&i_event';
   end;
   /

SELECT TO_CHAR (sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,session_state,
       SUBSTR (program, 1, 30) oprogram,
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR (event, 0, 15) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj#||':'||current_file#||':'||current_block#  obj
  FROM GV$ACTIVE_SESSION_HISTORY
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND event = :i_event
UNION ALL
SELECT TO_CHAR (sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,session_state,
       SUBSTR (program, 1, 30) oprogram,
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR (event, 0, 15) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj#||':'||current_file#||':'||current_block#  obj
  FROM DBA_HIST_ACTIVE_SESS_HISTORY
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND event = :i_event
ORDER BY TIME, sqlid
/

