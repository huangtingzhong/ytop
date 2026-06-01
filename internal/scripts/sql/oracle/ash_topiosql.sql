-- File Name: ash_topiosql.sql
-- Purpose: Oracle ASH Topiosql
-- Created: 20260516  by  huangtingzhong

--------------------------------------------------------------------------------
--
-- File name:   ashtopwait.sql
-- Author:      htz
-- Copyright:   htz@olm.com.cn
--
--------------------------------------------------------------------------------

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000
col time for a19 heading 'sample_time'
col sess_id for a15 heading 'session|serial#'
col sqlid for a18 heading 'sql_id|child_number'
col pn_text for a30 heading 'P1_TEXT:P2_TEXT:P3_TEXT'
col pn for a20 heading 'P1:P2:P3'
col oevent for a30 heading 'Event'
col oprogram for a15 heading 'PROGRAM'
col obj for a15 heading 'waiting|obj#:file#block#'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display event information from ash                                     |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT b_hours prompt 'Enter Search Hours Ago (i.e. 3) : '
ACCEPT e_hours prompt 'Enter How Many Hours  (i.e. 3) : '
variable b_hours number;
variable e_hours number;
begin
   :e_hours:=&e_hours;
   :b_hours:=&b_hours;
   end;
   /

SELECT ash.sql_id, COUNT (*)  total,sum(wait_time),sum(time_waited) 
  FROM GV$ACTIVE_SESSION_HISTORY ash, v$event_name evt
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND ash.session_state = 'WAITING'
       AND ash.event_id = evt.event_id
       AND evt.wait_class = 'User I/O'
       group by sql_id
UNION ALL
SELECT ash.sql_id, COUNT (*) total,sum(wait_time),sum(time_waited)
  FROM DBA_HIST_ACTIVE_SESS_HISTORY ash, v$event_name evt
 WHERE     SAMPLE_TIME >= SYSDATE - :b_hours / 24
       AND SAMPLE_TIME <= SYSDATE - (:b_hours - :e_hours) / 24
       AND ash.session_state = 'WAITING'
       AND ash.event_id = evt.event_id
       AND evt.wait_class = 'User I/O'
       group by sql_id
       order by total;

clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on


