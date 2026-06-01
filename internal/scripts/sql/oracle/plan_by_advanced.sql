-- File Name: plan_by_advanced.sql
-- Purpose: Oracle Plan By Advanced
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 1000
undefine sqlid;
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number,format=>'advanced')) t
 where s.sql_id = '&&sqlid'
/
set lines 78 pages 50
undefine sqlid;