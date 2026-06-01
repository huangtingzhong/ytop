-- File Name: sess_by_kgllkhdl.sql
-- Purpose: Oracle session By Kgllkhdl
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
break on inst_id
SELECT SUBSTR(b.event, 1, 25) event,
       SUBSTR(b.program, 1, 22) program,
       b.username||':'||last_call_et||':'||b.seq# u_s,
       b.sid || ':' || b.serial# || ':' || c.spid os_sess,
       substr(b.status || ':' || b.state,1,19) status,     
       a.name command,
       DECODE(b.sql_id, '0', b.prev_sql_id, '',b.prev_sql_id,b.sql_id) || ':' ||
       sql_child_number sql_id,
       b.BLOCKING_SESSION_STATUS || ':' || b.BLOCKING_INSTANCE || ':' ||
       b.BLOCKING_SESSION block_s,
       row_wait_file# || ':' || row_wait_obj# || ':' || row_wait_block# || ':' ||
       row_wait_row# row_wait
  FROM v$session b, v$process c, v$session_wait s, sys.audit_actions a
 WHERE b.paddr = c.addr
   AND s.SID = b.SID
   and a.action = b.command
   and b.saddr in (select KGLLKUSE from dba_kgllock where kgllkhdl='&dba_kgllock_kgllkhdl' and kgllkmod >=nvl('&kgllkmod',2)
   order by sql_id
/     