-- File Name: plan_by_bind.sql
-- Purpose: Oracle Plan By Bind
-- Created: 20260516  by  huangtingzhong

set pages 9999
set lines 150
--select * from table(dbms_xplan.display_cursor('&sql_id','&child_no','typical +peeked_binds'))
undefine sqlid;
select t.*
  from v$sql s,
       table(dbms_xplan.display_cursor(s.sql_id, s.child_number,'typical +peeked_binds')) t
 where s.sql_id = '&sqlid';
/
undefine sqlid;