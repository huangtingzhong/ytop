-- File Name: awr_control.sql
-- Purpose: Oracle AWR Control
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set feedback off
set lines 170
set pages 1000
col topsql for a15

PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display awr snapshot control info                                      |
PROMPT +------------------------------------------------------------------------+ 
PROMPT

Select extract(day from snap_interval) * 24 * 60 +
       extract(hour from snap_interval) * 60 +
       extract(minute from snap_interval) "Snapshot Interval",
       extract(day from retention) * 24 * 60 +
       extract(hour from retention) * 60 + extract(minute from retention) "Retention Interval(Minutes) ",
       extract(day from retention) "Retention(in Days) ",topnsql
  from dba_hist_wr_control
/
clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

