-- File Name: sess_mem_9i.sql
-- Purpose: Oracle session Mem 9i
-- Created: 20260516  by  huangtingzhong

set echo off
set pages 1000
set lines 200
col sess   for a10;
col status for a10;
col username for a10;
col client for a30;
col osuser for a10;
col program for a20;
col command for a10;
set verify off
col sess for a20 heading 'sid:serial#:ospid'
col session_pga_memory for 99999 heading 'Session|Pga_Memory'
col session_pga_memory_max for 99999 heading 'Session_Max|Pga_Memory'
col session_uga_memory for 99999 heading 'Session|Uga_Memory'
col session_uga_memory_max for 99999 heading 'Session_Max|Uga_Memory'
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session about pga memory used                                |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display session mem:active,INACTIVE,all                                |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT status prompt 'Enter Search Status (i.e. active|all|INACTIVE) : '
ACCEPT sid prompt 'Enter Search SID (i.e. 123|0(all)) : '
ACCEPT type prompt 'Enter Search Session Type (i.e. U(user)|B(background)|A(ALL)) : '

  SELECT a.sid || ',' || a.serial#||':'||b.spid AS sess,
         a.username,
         a.status,
         SUBSTR (a.program, 1, 20) program,
         substr(a.osuser || '@' || a.machine || '@' || a.process,1,30) AS client,
         DECODE (a.sql_hash_value, 0, a.prev_hash_value, a.sql_hash_value)
            sess_sql_hash,
         TO_CHAR (a.logon_time, 'mm-dd hh24:mi') AS logon_time,
         ROUND (sstat1.VALUE / 1024 / 1024, 2) session_pga_memory,
         ROUND (sstat2.VALUE / 1024 / 1024, 2) session_pga_memory_max,
         ROUND (sstat3.VALUE / 1024 / 1024, 2) session_uga_memory,
         ROUND (sstat4.VALUE / 1024 / 1024, 2) session_uga_memory_max
    FROM sys.v_$session a,
         sys.v_$process b,
         v$sesstat sstat1,
         v$sesstat sstat2,
         v$sesstat sstat3,
         v$sesstat sstat4,
         v$statname statname1,
         v$statname statname2,
         v$statname statname3,
         v$statname statname4
   WHERE     b.addr = a.paddr
         AND a.status =
                DECODE (UPPER ('&status'),
                        'ALL', a.status,
                        'ACTIVE', 'ACTIVE',
                        'INACTIVE')
         AND a.TYPE =
                DECODE (UPPER ('&type'),
                        'U', 'USER',
                        'B', 'BACKGROUND',
                        'A', a.TYPE)
         AND a.sid = DECODE (&sid, 0, a.sid, &sid)
         AND a.sid = sstat1.sid
         AND a.sid = sstat2.sid
         AND a.sid = sstat3.sid
         AND a.sid = sstat4.sid
         AND statname1.statistic# = sstat1.statistic#
         AND statname2.statistic# = sstat2.statistic#
         AND statname3.statistic# = sstat3.statistic#
         AND statname4.statistic# = sstat4.statistic#
         AND statname1.name = 'session pga memory'
         AND statname2.name = 'session pga memory max'
         AND statname3.name = 'session uga memory'
         AND statname4.name = 'session uga memory max'
ORDER BY session_pga_memory
/
set echo on
set pages 5
set lines 75



