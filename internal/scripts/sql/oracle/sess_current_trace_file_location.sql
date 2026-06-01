-- File Name: sess_current_trace_file_location.sql
-- Purpose: Oracle session Current Trace File Location
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000

SET TERMOUT OFF;

SET ECHO        OFF
SET FEEDBACK    6
SET HEADING     ON
SET LINESIZE    180
SET PAGESIZE    50000
SET TERMOUT     ON
SET TIMING      OFF
SET TRIMOUT     ON
SET TRIMSPOOL   ON
SET VERIFY      OFF

CLEAR COLUMNS
CLEAR BREAKS
CLEAR COMPUTES

COLUMN "Trace File Path" FORMAT a80 HEADING 'Your trace file with path is:'

SELECT
    a.trace_path || '/' || b.trace_file "Trace File Path"
FROM
    (  SELECT value trace_path 
       FROM   v$parameter 
       WHERE  name='user_dump_dest'
    ) a
  , (  SELECT c.instance || '_ora_' || spid ||'.trc' TRACE_FILE 
       FROM   v$process,
              (select lower(instance_name) instance from v$instance)  c
       WHERE  addr = ( SELECT paddr 
                       FROM v$session 
                       WHERE (audsid, sid) = (  SELECT
                                                    sys_context('USERENV', 'SESSIONID')
                                                  , sys_context('USERENV', 'SID') 
                                                FROM dual
                                              )
                     )
    ) b
/
