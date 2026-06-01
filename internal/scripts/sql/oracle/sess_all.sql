-- File Name: sess_all.sql
-- Purpose: Oracle session All
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 270;
col sess   for a15 heading 'sess:serial|os process';
col status for a10;
col username for a10;
col client for a25;
col osuser for a10;
col program for a30;
col command for a10;
set verify off
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session :active,INACTIVE,all                                   |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
       a.username,
       a.status,
       SUBSTR(a.program, 1, 39) program,
       a.osuser || '@' || a.machine || '@' || a.process AS client,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       DECODE(a.sql_id, '0', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       b.name AS command,
       TO_CHAR(a.logon_time, 'mm-dd hh24:mi') AS logon_time
  FROM v$session a, audit_actions b, v$process c
 WHERE a.command = b.action
   AND a.paddr = c.addr
 ORDER BY program, process
/
