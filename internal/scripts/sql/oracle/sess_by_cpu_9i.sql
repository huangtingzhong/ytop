-- File Name: sess_by_cpu_9i.sql
-- Purpose: Oracle session By Cpu 9i
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 200;
col sess   for a20 heading 'sess:serial|os process';
col username for a15;
col client for a24;
col osuser for a10;
col program for a30;
col command for a20;
set verify off
col sql_hash for a20 heading 'SQL|HASH_VALUE'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col user_stat for a25 heading 'USERNAME.STATUS'
col last_call_et for 9999999 heading 'LAST|CALL_ET'
col event for a40
SELECT a.sid || '.' || a.serial# || '.' || c.spid AS sess,
       a.username||'.'||
       a.status user_stat,
       a.LAST_CALL_ET,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process,1,24) AS client,
       DECODE(a.SQL_HASH_VALUE, '0', a.PREV_HASH_VALUE, a.SQL_HASH_VALUE) hash_value,
       b.name AS command,
       TO_CHAR(a.logon_time, 'mm-dd hh24:mi') AS logon_time,
       substr(d.event,0,39) as "event"
  FROM v$session a, audit_actions b, v$process c,v$session_wait d
 WHERE a.command = b.action(+)
   AND a.paddr = c.addr
   AND a.username IS NOT NULL
   and a.sid=d.sid(+)
   AND c.spid = nvl('&spid',c.spid)
 ORDER BY last_call_et 
/