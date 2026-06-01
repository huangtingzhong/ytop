-- File Name: sess_commit.sql
-- Purpose: Oracle session Commit
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
col seq# for 999999999 heading 'seq#'
col redo_size for 99999999999 heading 'REDO_SIZE(M)'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session :active,INACTIVE,all                                   |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT status prompt 'Enter Search Status (i.e. active(default)|all|INACTIVE) : ' default 'active'
ACCEPT sid prompt 'Enter Search Sid (i.e. 123|0(all default)) : ' default 0


SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
       a.username,
       a.status,
       a.seq#,
       SUBSTR(a.program, 1, 25) program,
       substr(a.osuser || '@' || a.machine || '@' || a.process,1,24) AS client,
       a.BLOCKING_SESSION_STATUS || ':' || a.BLOCKING_INSTANCE || ':' ||
       a.BLOCKING_SESSION block_s,
       DECODE(a.sql_id, '0', a.prev_sql_id, a.sql_id) || ':' ||
       sql_child_number sql_id,
       b.name AS command,
       e.value
  FROM v$session a, audit_actions b, v$process c,v$statname d,v$sesstat e
 WHERE a.command = b.action
   AND a.paddr = c.addr
   AND a.username IS NOT NULL
   AND a.status = DECODE(UPPER('&status'),
                         'ALL',
                         a.status,
                         'ACTIVE',
                         'ACTIVE',
                         'INACTIVE')
   AND a.sid = decode(&sid, 0, a.sid, &sid)
   AND e.STATISTIC# =d.STATISTIC# 
   and e.sid=a.sid
   and d.name='user commits'
--and  a.command>0
 ORDER BY value
/