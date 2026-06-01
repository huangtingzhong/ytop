-- File Name: plan_by_sqlid.sql
-- Purpose: Oracle Plan By Sqlid
-- Created: 20260516  by  huangtingzhong

set echo off
set pagesize 0
SET VERIFY OFF
set lines 200 heading off


prompt
prompt ****************************************************************************************
prompt AWR
prompt **************************************************************************************** 
select * from table(dbms_xplan.display_awr('&sqlid',null,null));

set pages 10000 heading on
prompt ****************************************************************************************
prompt CURSOR
prompt ****************************************************************************************

select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number)) t
 where s.sql_id = '&sqlid';
undefine sqlid
set heading on
set pages 40
set echo on