-- File Name: user_alter_password_using_old.sql
-- Purpose: Oracle User Alter Password Using Old
-- Created: 20260516  by  huangtingzhong

set long 3000 heading off pages 0
undefine username;
with t as
 ( select dbms_metadata.get_ddl('USER',upper('&username') ddl from dual )
 select replace(substr(ddl,1,instr(ddl,'DEFAULT')-1),'CREATE','ALTER')||';'  alteruser
 from t;
undefine username;
set heading on pages 1000