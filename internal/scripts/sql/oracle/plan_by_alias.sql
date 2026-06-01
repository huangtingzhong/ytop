-- File Name: plan_by_alias.sql
-- Purpose: Oracle Plan By Alias
-- Created: 20260516  by  huangtingzhong

set echo off
set lines 200 pages 1000
select * from table(dbms_xplan.display_cursor('&sql_id','&child_no','alias'))
/
set lines 78 pages 50