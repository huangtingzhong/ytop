-- File Name: log_current.sql
-- Purpose: Oracle Log Current
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display current log used info  include seq ,size                       |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
select le.leseq "Current log sequence No",
       100 * cp.cpodr_bno / le.lesiz "Percent Full",
       (cpodr_bno - 1) * 512  "bytes used exclude header",
       le.lesiz * 512 - cpodr_bno * 512 "Left space",
       le.lesiz  *512       "logfile size"
  from x$kcccp cp, x$kccle le
 where LE.leseq = CP.cpodr_seq
   and bitand(le.leflg, 24) = 8
/
clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

