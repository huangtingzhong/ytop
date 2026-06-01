-- File Name: sess_9i.sql
-- Purpose: Oracle session 9i
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 2000;
col sess   for a20 heading 'sess:serial|os process';
col username for a15;
col client for a25;
col osuser for a10;
col program for a30;
col command for a20;
set verify off
col sql_hash for a20 heading 'SQL|HASH_VALUE'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col user_stat for a25 heading 'USERNAME.STATUS'
col event1 for a31 heading 'EVENT'
col last_call_et for 9999999 heading 'LAST|CALL_ET'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session :active,INACTIVE,all                                   |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT status prompt 'Enter Search Status (i.e. active(default)|all|INACTIVE) : ' default 'active'
ACCEPT sid prompt 'Enter Search Sid (i.e. 123|0(all default)) : ' default 0
ACCEPT spid prompt 'Enter Search Os process number (i.e. 123|0(all default)) : ' default 0
ACCEPT program prompt 'Enter Search Program (i.e. (J000)|(all)default)) : ' default ''

SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
       a.username||'.'||
       a.status user_stat,
       a.LAST_CALL_ET,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process,1,24) AS client,
       DECODE(a.SQL_HASH_VALUE, '0', a.PREV_HASH_VALUE, a.SQL_HASH_VALUE) hash_value,
       b.name AS command,
       TO_CHAR(a.logon_time, 'mm-dd hh24:mi') AS logon_time,
       substr(d.event,1,30) event1
  FROM v$session a, audit_actions b, v$process c,v$session_wait d
 WHERE a.command = b.action(+)
   AND a.paddr = c.addr(+)
   AND a.username IS NOT NULL
   and a.sid=d.sid(+)
   AND a.program like upper('%&program%')
   AND a.status = DECODE(UPPER('&status'),
                         'ALL',
                         a.status,
                         'ACTIVE',
                         'ACTIVE',
                         'INACTIVE')
   AND a.sid = decode(&sid, 0, a.sid, &sid)
   AND c.spid = decode(&spid, 0, c.spid, &spid)
--and  a.command>0
 ORDER BY last_call_et 
/
