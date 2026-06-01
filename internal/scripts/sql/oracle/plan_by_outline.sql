-- File Name: plan_by_outline.sql
-- Purpose: Oracle Plan By Outline
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 heading off VERIFY OFF pagesize 0
undefine sqlid;
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number,'OUTLINE')) t
 where s.sql_id = '&sqlid';

undefine sqlid;
