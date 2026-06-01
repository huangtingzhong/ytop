-- File Name: plan_by_adaptive.sql
-- Purpose: Oracle Plan By Adaptive
-- Created: 20260516  by  huangtingzhong

set echo off
set pagesize 0
SET VERIFY OFF
set lines 200 heading off
ACCEPT sqlid prompt 'Enter sql_id (i.e. CONTROL) : '
--ACCEPT child_no prompt 'Enter chinld number (i.e. o) : '

prompt
prompt ****************************************************************************************
prompt AWR
prompt **************************************************************************************** 
--select * from table(dbms_xplan.display_awr('&sqlid',null,null,'advanced allstats'));
select * from table(dbms_xplan.display_awr('&sqlid',null,null));
--spool _plan.sql
----SELECT 'select * from table(dbms_xplan.display_cursor(''&sqlid'','||CHILD_NUMBER||',''ADVANCED ALLSTATS''));' FROM (
--SELECT 'select * from table(dbms_xplan.display_cursor(''&sqlid'','||CHILD_NUMBER||'));' FROM (
--  SELECT CHILD_NUMBER,ROW_NUMBER() OVER(PARTITION BY PLAN_HASH_VALUE ORDER BY CHILD_NUMBER) rn 
--  FROM V$SQL WHERE SQL_ID = '&sqlid'
--) WHERE rn=1;
--spool off
set pages 10000 heading on
prompt ****************************************************************************************
prompt CURSOR
prompt ****************************************************************************************
--@_plan.sql
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number,'adaptive')) t
 where s.sql_id = '&sqlid';
undefine sqlid
set heading on
set pages 40
set echo on
