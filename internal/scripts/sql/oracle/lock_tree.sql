-- File Name: lock_tree.sql
-- Purpose: Oracle Show row and table lock wait tree
-- Created: 20260516  by  huangtingzhong

SET ECHO OFF
SET PAGESIZE 2000
SET LINESIZE 200
SET HEADING ON
COL event FORMAT a25
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|LAST_CALL|SEQ#'
COL client FOR a31
col sql_id for a18
COL row_wait  for a22 heading 'ROW_WAIT|FILE#:OBJ#:BLOCK#:ROW#'
col logon_time for a12
col status for a20  heading 'STATUS|STATE'
col command for a15
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col inst_id for 9 heading 'I'
col root_sid for a15
break on inst_id
SELECT LPAD(' ', (level-1)*2, ' ')||'-'||
       CONNECT_BY_ROOT(f.sid) root_sid,
       SUBSTR(f.event, 1, 25) event,
       SUBSTR(f.program, 1, 22) program,
       f.username || ':' || f.last_call_et || ':' || f.seq# u_s,
       f.sid || ':' || f.serial# || ':' || f.spid os_sess,
       substr(f.status || ':' || f.state, 1, 19) status,
       f.name command,
       DECODE(f.sql_id, '0', f.prev_sql_id, '', f.prev_sql_id, f.sql_id) || ':' ||
       sql_child_number sql_id,
       f.BLOCKING_SESSION_STATUS || ':' || f.BLOCKING_INSTANCE || ':' ||
       f.BLOCKING_SESSION block_s
  from (select b.event,
               b.program,
               b.username,
               last_call_et,
               b.seq#,
               b.sid,
               b.serial#,
               c.spid,
               b.status,
               b.state,
               a.name,
               b.sql_id,
               b.prev_sql_id,
               sql_child_number,
               b.BLOCKING_SESSION_STATUS,
               b.BLOCKING_INSTANCE,
               b.BLOCKING_SESSION
          FROM v$session         b,
               v$process         c,
               v$session_wait    s,
               sys.audit_actions a
         where b.paddr = c.addr
           AND s.SID = b.SID
           and a.action = b.command
           and b.username is not null) f
CONNECT BY PRIOR f.sid = f.blocking_session
 START WITH f.blocking_session IS NULL
;
    
 