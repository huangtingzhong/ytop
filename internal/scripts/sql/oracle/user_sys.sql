-- File Name: user_sys.sql
-- Purpose: Oracle User Sys
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set lines 170
set pages 10
col SYSDBA for a6
col SYSOPER for a7
col SYSASM for a6
PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | display user with sys                                                  |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
select * from gv$pwfile_users
/
clear    breaks  
set verify on
set linesize 78 termout on feedback 6 heading on;
set echo on
