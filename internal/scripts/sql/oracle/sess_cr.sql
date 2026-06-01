-- File Name: sess_cr.sql
-- Purpose: Oracle session Cr
-- Created: 20260516  by  huangtingzhong

set echo off
store set sqlplusset replace

set verify off
set serveroutput on
set feedback off
set lines 200
set pages 1000
alter session set nls_date_format='yyyy-mm-dd hh24:mi:ss';
col t_sid for a20 heading 'SID:SERIAL:OSPID'
col t_user for a20 heading 'USERNAME:STATUS'
col t_name for a15 heading 'COMMAND'
col t_pro for a25 heading 'PROGRAM'
col t_mac for a25 heading 'MACHINE'
col block_s for a15 heading 'BLOCKING SESSION'
col io for  a30 heading 'LOG_IO:PHY_IO|CR_GET:CR_CHANGE'
col sql_id for a19
col start_time for a18
select se.sid || ':' || se.serial# || ':' || pr.spid t_sid,
       us.username || ':' || se.status t_user,
       au.name t_name,
       substr(pr.program,1,25) t_pro,
       substr(se.MACHINE,1,25) t_mac,
       se.BLOCKING_SESSION_STATUS || ':' || se.BLOCKING_INSTANCE || ':' ||
       se.BLOCKING_SESSION block_s,
       DECODE(se.sql_id, '0', se.prev_sql_id, se.sql_id) || ':' ||
       sql_child_number sql_id,
       tr.LOG_IO||':'||tr.PHY_IO||':'||tr.CR_GET||':'||tr.CR_CHANGE io,
       tr.START_TIME
  from v$session     se,
       v$transaction tr,
       dba_users     us,
       v$process     pr,
       audit_actions au
 where se.taddr = tr.addr
   and se.user# = us.user_id
   and pr.addr = se.paddr
   and au.action = se.COMMAND;
clear    breaks  
@sqlplusset