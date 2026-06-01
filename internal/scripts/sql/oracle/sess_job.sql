-- File Name: sess_job.sql
-- Purpose: Oracle session Job
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set heading on
set pages 1000
set lines 270;
COL os_sess FOR a25 heading 'SESS_SERIAL|OSPID'
col u_s for a22 heading 'USERNMAE|LAST_CALL|SEQ#'
col program for a30;
col sql_id for a19 
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col seq# for 999999999 heading 'seq#'
col job for 99999 heading 'JOB_ID'
col inst_id for 9 heading 'I'
COL event FORMAT a25
break on inst_id

SELECT /*+ noparallel */a.inst_id,
       a.username || ':' || a.last_call_et || ':' || a.seq# u_s,
       a.sid || ':' || a.serial# || ':' || c.spid os_sess,
       SUBSTR(a.program, 1, 25) program,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       DECODE(a.sql_id, '0', 'p_'||a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       d.job,
       SUBSTR(a.event, 1, 25) event
  FROM gv$session a,
       audit_actions b,
       gv$process c,
       (select v.inst_id, v.SID, v.id2 JOB, j.what
          from sys.job$ j, gv$lock v
         where v.type = 'JQ'
           and j.job(+) = v.id2) d
 WHERE a.command = b.action
   and a.inst_id = d.inst_id
   and a.inst_id = c.inst_id
   AND a.paddr = c.addr
   AND a.sid = d.sid
   AND a.sid = nvl('&sid', a.sid)
--and  a.command>0
 ORDER BY inst_id, u_s
/
undefine sid;
