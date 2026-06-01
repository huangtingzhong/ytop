-- File Name: sess_by_cpu.sql
-- Purpose: Oracle session By Cpu
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
ACCEPT spid  prompt 'Enter Search Process Number (i.e. 1234) : '

select a.sid||','||a.serial# as sess ,a.username,a.status,substr(a.program,1,39) program
,a.osuser||'@'||a.machine||'@'||a.process  as client,         DECODE (a.sql_hash_value, 0, a.prev_hash_value, a.sql_hash_value)
            sess_sql_hash,
            DECODE (a.sql_id, '0', a.prev_sql_id, a.sql_id)
         || ':'
         || sql_child_number
            sql_id,
to_char(a.logon_time,'mm-dd hh24:mi') as logon_time
,substr(a.event ,1,30) event 
from v$session a ,v$process b WHERE a.paddr = b.addr and  b.spid = &spid
/
clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

