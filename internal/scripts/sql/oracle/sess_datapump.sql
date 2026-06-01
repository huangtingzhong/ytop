-- File Name: sess_datapump.sql
-- Purpose: Oracle session Datapump
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 300
set pages 40
set heading on
col inst_id for 99 heading 'I'
col s_s     for a15    heading 'SID.OS_PID'
col l_s     for a15    heading 'LAST_CALL|SEQ#'
col program for a30    heading 'PROGRAM'
col status  for a15    heading 'STATUS'
col u_o     for a30    heading 'USERNAME|JOB_OWNER_NAME'
col job_name for a30   heading 'JOB_NAME'
col session_type for a15 heading 'SESSION_TYPE' 
select s.inst_id,
       s.sid || '.' || p.spid s_s,
       s.last_call_et || '.' || s.seq# l_s,
       s.program,
       s.status,
       s.username||'.'||d.OWNER_NAME u_o,
       d.job_name,
       d.SESSION_TYPE
  from gv$session s, gv$process p, dba_datapump_sessions d
 where p.addr = s.paddr
   and s.saddr = d.saddr
   and s.inst_id = p.inst_id
/