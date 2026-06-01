-- File Name: ash_oneevent1.sql
-- Purpose: Oracle ASH Oneevent1
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300 pages 5000 verify off heading on
col time for a19 heading 'sample_time'
col sess_id for a15 heading 'session|serial#'
col sqlid for a18 heading 'sql_id|child_number'
col pn_text for a30 heading 'P1_TEXT:P2_TEXT:P3_TEXT'
col pn for a20 heading 'P1:P2:P3'
col oevent for a20 heading 'Event'
col oprogram for a15 heading 'PROGRAM'
col obj for a15 heading 'waiting|obj#:file#block#'
break on time



SELECT TO_CHAR(sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,
       BLOCKING_SESSION || '.' || BLOCKING_SESSION_SERIAL# block,
       session_state,
       SUBSTR(program, 1, 30) oprogram,
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR(event, 0, 20) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj# || ':' || current_file# || ':' || current_block# obj
  FROM GV$ACTIVE_SESSION_HISTORY
 where sample_id = &&sample_id
   AND event = '&&event'
UNION ALL
SELECT TO_CHAR(sample_time, 'yyyy-mm-dd hh24:mi:ss') time,
       session_id || '-' || session_serial# sess_id,
       BLOCKING_SESSION || '.' || BLOCKING_SESSION_SERIAL# block,
       session_state,
       SUBSTR(program, 1, 30) oprogram,
       sql_id || ':' || sql_child_number sqlid,
       SUBSTR(event, 0, 20) oevent,
       p1text || ':' || p2text || ':' || p3text pn_text,
       p1 || ':' || p2 || ':' || p3 pn,
       current_obj# || ':' || current_file# || ':' || current_block# obj
  FROM DBA_HIST_ACTIVE_SESS_HISTORY
 where sample_id = &&sample_id
   AND event = '&&event'
 ORDER BY TIME, sqlid
/
