-- File Name: sess_by_event.sql
-- Purpose: Oracle session By Event
-- Created: 20260516  by  huangtingzhong

SET ECHO OFF
SET PAGESIZE 2000
SET LINESIZE 200
SET HEADING ON
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
COL client FOR a31
col username for a15
col sql_id for a18
COL row_wait  for a22 heading 'ROW_WAIT|FILE#:OBJ#:BLOCK#:ROW#'
col logon_time for a12
col status for a20  heading 'STATUS|STATE'
col command for a15
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col wait_time for a10 heading 'TOTAL_TIME|CURRENT_TIME'
col inst_id for 9 heading 'I'
col last_seq for a15 heading 'LAST_CALL_ET|SEQ#'
break on inst_id
SELECT b.inst_id,
       b.sid || ':' || b.serial# || ':' || c.spid os_sess,
       b.last_call_et || '.' || b.seq# last_seq,
       b.wait_time || '.' || (b.SECONDS_IN_WAIT - b.WAIT_TIME) wait_time,
       SUBSTR(b.program, 1, 22) program,
       b.username,
       substr(b.status || ':' || b.state, 1, 19) status,
       a.name command,
       DECODE(b.sql_id, '0', b.prev_sql_id, b.sql_id) || ':' ||
       sql_child_number sql_id,
       b.BLOCKING_SESSION_STATUS || ':' || b.BLOCKING_INSTANCE || ':' ||
       b.BLOCKING_SESSION block_s,
       row_wait_file# || ':' || row_wait_obj# || ':' || row_wait_block# || ':' ||
       row_wait_row# row_wait
  FROM gv$session b, gv$process c, gv$session_wait s, sys.audit_actions a
 WHERE b.paddr = c.addr
   AND s.SID = b.SID
   and b.inst_id = c.inst_id
   and c.inst_id = s.inst_id
   and a.action = b.command
   and s.event = '&event_name'
 order by inst_id,block_s
/