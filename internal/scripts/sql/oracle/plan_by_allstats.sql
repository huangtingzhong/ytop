-- File Name: plan_by_allstats.sql
-- Purpose: Oracle Plan By Allstats
-- Created: 20260516  by  huangtingzhong

set lines 180
select * from table(dbms_xplan.display_cursor('&sql_id','&child_no','allstats  +peeked_binds'))
/
