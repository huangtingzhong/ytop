-- File Name: plan_by_explain.sql
-- Purpose: Oracle Plan By Explain
-- Created: 20260516  by  huangtingzhong

set lines 170 
set pages 1000
select * from table(dbms_xplan.display(format=>'OUTLINE'));
