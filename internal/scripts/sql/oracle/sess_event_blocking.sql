-- File Name: sess_event_blocking.sql
-- Purpose: Oracle session Event Blocking
-- Created: 20260516  by  huangtingzhong

set pages 1000
set lines 270;
col sess   for a20 heading 'sess:serial|os process';
col status for a10;
col username for a15;
col client for a25;
col osuser for a10;
col program for a30;
col command for a20;
set verify off
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col seq# for 999999999 heaidng 'seq#'
col event for a26
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session                                |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       substr(a.event,1,25) event,
       a.username,
       a.status,
       a.seq#,
       SUBSTR(a.program, 1, 25) program,
       DECODE(a.sql_id, '0', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       b.name AS command
  FROM v$session a, audit_actions b, v$process c
 WHERE a.command = b.action
   AND a.paddr = c.addr
   AND a.username IS NOT NULL
--and  a.command>0
  order by event
/


