-- File Name: sess_idle_time.sql
-- Purpose: Oracle session Idle Time
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
col inst_id for 9999999	
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col seq# for 999999999 heading 'seq#'

break on inst_id
ACCEPT sid prompt 'Enter Search Sid (i.e. 123|0(all default)) : ' default 0

SELECT a.inst_id,a.sid || ':' || a.serial# || ':' || c.spid AS sess,
       a.username,
       a.status,
       a.seq#,
       round(seconds_in_wait/60/60,2) wait_hours,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process,1,24) AS client,
       b.name AS command
  FROM gv$session a, audit_actions b, gv$process c
 WHERE a.command = b.action
   AND a.paddr = c.addr
   and a.inst_id=c.inst_id
   AND a.sid = decode(&sid, 0, a.sid, &sid)
   AND a.wait_class='Idle'
   and a.status<>'ACTIVE'
 ORDER BY inst_id,wait_hours
/