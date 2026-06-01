-- File Name: awr_create.sql
-- Purpose: Oracle Create a manual AWR snapshot
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off
set serveroutput on
set lines 170
set pages 1000


PROMPT
PROMPT +------------------------------------------------------------------------+
PROMPT | minual create awr snapshot                                             |
PROMPT +------------------------------------------------------------------------+ 
PROMPT
exec DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT();

clear    breaks  
set verify on
set serveroutput off
set feedback on
set linesize 78 termout on feedback 6 heading on;
SET SERVEROUTPUT off
set echo on

