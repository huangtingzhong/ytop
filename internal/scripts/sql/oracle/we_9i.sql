-- File Name: we_9i.sql
-- Purpose: Oracle We 9i
-- Created: 20260516  by  huangtingzhong

SET ECHO OFF
SET PAGESIZE 2000
SET LINESIZE 200
SET HEADING ON
COL event FORMAT a25
COL program FORMAT a23
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
COL client FOR a31
col hash_value for 999999999999
COL row_wait  for a22 heading 'ROW_WAIT|FILE#:OBJ#:BLOCK#:ROW#'
col logon_time for a12
col user_stat for a30  heading 'USER_NAME|STATUS'
col command for a15
col inst_id for 9 heading 'I'
col seq# for 999999999
col last_call_et for 9999999 heading 'LAST|CALL_ET'
break on inst_id
SELECT b.inst_id,SUBSTR(s.event, 1, 25) event,
       SUBSTR(b.program, 1, 22) program,
       b.username||'.'||b.status user_stat,
       b.sid || ':' || b.serial# || ':' || c.spid os_sess,    
       b.LAST_CALL_ET,
       a.name command,
       DECODE(b.SQL_HASH_VALUE, '0', b.PREV_HASH_VALUE, b.SQL_HASH_VALUE) hash_value,
       row_wait_file# || ':' || row_wait_obj# || ':' || row_wait_block# || ':' ||
       row_wait_row# row_wait
  FROM gv$session b, gv$process c, gv$session_wait s, sys.audit_actions a
 WHERE b.paddr = c.addr
   AND s.SID(+)= b.SID
   AND s.inst_id=b.inst_id
   and b.inst_id=c.inst_id
   and c.inst_id=s.inst_id
   and a.action = b.command
   and b.status = 'ACTIVE'
   and b.username is not null
 order by inst_id,last_call_et
/      
       
select b.inst_id,DECODE(b.SQL_HASH_VALUE, '0', b.PREV_HASH_VALUE, b.SQL_HASH_VALUE) hash_value, a.name command, count(*)
  from gv$session b, sys.audit_actions a
 where username is not null
   and status = 'ACTIVE'
   and a.action = b.command
 group by inst_id,DECODE(b.sql_hash_value, '0', b.prev_hash_value, b.sql_hash_value), a.name
 order by inst_id,4 desc;



col event for a40

select b.inst_id,event,
       DECODE(a.SQL_HASH_VALUE, '0', a.PREV_HASH_VALUE, a.SQL_HASH_VALUE) hash_value,
       count(*)
  from gv$session_wait b,gv$session a
 where a.status = 'ACTIVE'
   and a.username is not null
   and b.inst_id=a.inst_id
   and a.sid=b.sid(+)
 group by b.inst_id,event, DECODE(a.sql_hash_value, '0', a.prev_hash_value, a.sql_hash_value) 
 order by inst_id;

 
clear    breaks  
