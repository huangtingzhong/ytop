-- File Name: plan_by_last.sql
-- Purpose: Oracle Plan By Last
-- Created: 20260516  by  huangtingzhong

set echo off
set verify off 
set lines 200
set pages 200
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(nvl('&sqlid',null),null,'ALLSTATS LAST'));
set pages 40
set echo on
