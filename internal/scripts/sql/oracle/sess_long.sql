-- File Name: sess_long.sql
-- Purpose: Oracle session Long
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off heading on pages 100
set serveroutput on
set feedback off
set lines 300
col sid for 9999999999
col command for  a15
col opname for a30
col seq for 999999999
col target for a20 heading 'OPT_OBJECT'
col sofar for 9999999999999
col totalwork for 999999999999
col time for a50        heading "Begin TIME_LAST_UPTIME_TIME_END_TIME"
col units for a10
col time_remaining for 9999999999 heading 'TIME|REMAINING'
col elapsed_seconds for 9999999999 heading 'ELAPSED|SECONDS'

PROMPT '--------------------------------------------------------------'
PROMPT '--------------------V$SESSION_LONGOPS-------------------------'
PROMPT '--------------------------------------------------------------'
SELECT a.sid,
       d.name command,
       a.opname,
       b.seq#,
       a.target,
       a.sofar,
       a.totalwork,
       a.units,
          TO_CHAR (a.start_time, 'yyyy-mm-dd hh24:mi:ss')
       || '-'
       || TO_CHAR (last_update_time, 'hh24:mi:ss')||'-'||to_char(sysdate+a.time_remaining/24/3600,'yyyy-mm-dd hh24:mi:ss') time,
       a.time_remaining,
       a.elapsed_seconds
  FROM v$session_longops a, v$session b, audit_actions d
 WHERE sofar <> totalwork AND a.sid = b.sid AND b.command = d.action and a.time_remaining >0
/


col sess   for a20 heading 'sess:serial|os process';
col username for a15;
col client for a25;
col osuser for a10;
col program for a30;
col command for a20;
col sql_id for a20 heading 'SQL_ID|SQL_CHILD_NUMBER'
col block_s for a15 heading 'BLOCK_SESS|INST:SESS'
col u_s_l for a45 heading 'USERNAME.STATUS|LAST_elapsed_time.SEQ#'

PROMPT '--------------------------------------------------------------'
PROMPT '--------------------V$SESSION LAST_CALL_ET--------------------'
PROMPT '--------------------------------------------------------------'
SELECT sess,
       u_s_l,
       program,
       client,
       block_s,
       sql_id,
       command
  FROM (  SELECT a.sid || ',' || a.serial# || '.' || c.spid AS sess,
                    a.username
                 || '.'
                 || a.status
                 || '.'
                 || a.LAST_CALL_ET
                 || '.'
                 || a.seq#
                    u_s_l,
                 SUBSTR (a.program, 1, 25) program,
                 SUBSTR (a.osuser || '@' || a.machine || '@' || a.process,
                         1,
                         24)
                    AS client,
                    a.BLOCKING_SESSION_STATUS
                 || ':'
                 || a.BLOCKING_INSTANCE
                 || ':'
                 || a.BLOCKING_SESSION
                    block_s,
                    DECODE (a.sql_id, '0', a.prev_sql_id, a.sql_id)
                 || ':'
                 || sql_child_number
                    sql_id,
                 b.name AS command,
                 a.LAST_CALL_ET
            FROM v$session a, audit_actions b, v$process c
           WHERE     a.command = b.action
                 AND a.paddr = c.addr
                 AND a.username IS NOT NULL
                 AND a.status = 'ACTIVE'
        ORDER BY LAST_CALL_ET DESC)
 WHERE ROWNUM < 50
 /
clear    breaks  


