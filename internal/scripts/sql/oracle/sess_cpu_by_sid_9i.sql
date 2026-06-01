-- File Name: sess_cpu_by_sid_9i.sql
-- Purpose: Oracle session Cpu By Sid 9i
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

col sess   for a10;
col status for a10;
col username for a10;
col client for a25;
col osuser for a10;
col program for a30;
col command for a10;
col sql_id for a18
col event for a30

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display one session info                               |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
ACCEPT sid  prompt 'Enter Search Process Number (i.e. 1234) : '

select a.sid||','||a.serial# as sess ,a.username,a.status,substr(a.program,1,39) program
,a.osuser||'@'||a.machine||'@'||a.process  as client,         DECODE (a.sql_hash_value, 0, a.prev_hash_value, a.sql_hash_value)
            sess_sql_hash,
to_char(a.logon_time,'mm-dd hh24:mi') as logon_time
,substr(c.event ,1,30) event 
from v$session a ,v$process b ,v$session_wait c WHERE a.paddr = b.addr and  a.sid = &sid and a.sid=c.sid;

clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on
