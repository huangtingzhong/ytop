-- File Name: lock_object.sql
-- Purpose: Oracle Lock Object
-- Created: 20260516  by  huangtingzhong

SET PAGESIZE 2000
SET LINESIZE 200
SET HEADING ON
COL event FORMAT a25
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|SEQ#'
COL client FOR a31
col sql_id for a18
col logon_time for a12
col status for a20  heading 'STATUS|STATE'
col command for a15
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col inst_id for 9 heading 'I'
col owner_name for a35 heading 'LOCK  OBJECT|OWNER_NAME'
break on inst_id
SELECT b.inst_id,
       SUBSTR(b.event, 1, 25) event,
       SUBSTR(b.program, 1, 22) program,
       b.username || ':' || b.seq# u_s,
       b.sid || ':' || b.serial# || ':' || c.spid os_sess,
       substr(b.status || ':' || b.state, 1, 19) status,
       a.name command,
       DECODE(b.sql_id, '0', b.prev_sql_id, b.sql_id) || ':' ||
       sql_child_number sql_id,
       lo.locked_mode,
       do.owner || '.' || do.object_name owner_name
  FROM gv$session        b,
       gv$process        c,
       gv$session_wait   s,
       sys.audit_actions a,
       gv$locked_object  lo,
       dba_objects       do
 WHERE b.paddr = c.addr
   AND s.SID = b.SID
   and c.inst_id = nvl('&inst_id', c.inst_id)
   and s.sid = nvl('&sid', s.sid)
   and b.inst_id = c.inst_id
   and c.inst_id = s.inst_id
   and lo.inst_id = b.inst_id
   and a.action = b.command
   and lo.object_id = do.object_id
   and lo.session_id = b.sid
   and do.object_id = lo.object_id
 order by inst_id, sql_id
/

undefine inst_id;
undefine sid;