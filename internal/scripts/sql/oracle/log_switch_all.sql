-- File Name: log_switch_all.sql
-- Purpose: Oracle Log Switch All
-- Created: 20260516  by  huangtingzhong

begin
 for log_cur in ( select group# group_no from v$log )
  loop
    execute immediate 'alter system archive log current';
  end loop;
 end;
/

