-- File Name: sess_by_client_cpu.sql
-- Purpose: Oracle session By Client Cpu
-- Created: 20260516  by  huangtingzhong

set echo off
set pages 1000
set lines 200;
col sess   for a20 heading 'sess:serial|os process';
col username for a15;
col client for a25;
col osuser for a10;
col program for a30;
col command for a20;
set verify off
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col u_s_l for a45 heading 'USERNAME.STATUS|LAST_elapsed_time.SEQ#'


SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
       a.username||'.'||
       a.status||'.'||
       a.LAST_CALL_ET||'.'|| 
       a.seq# u_s_l,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process,1,24) AS client,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       DECODE(a.sql_id, '0', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       b.name AS command,
       TO_CHAR(a.logon_time, 'mm-dd hh24:mi') AS logon_time
  FROM v$session a, audit_actions b, v$process c
 WHERE a.command = b.action
   AND a.paddr = c.addr
   AND a.process='&client_os_pid'
/

set echo on