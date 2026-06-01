-- File Name: user_grant_pri.sql
-- Purpose: Oracle User Grant Pri
-- Created: 20260516  by  huangtingzhong

-- Grant privileges: define user_list and perm_list (e.g. users and CREATE TABLE)
set echo off
set lines 300 heading on serveroutput on verify on
undefine user_list;
undefine perm_list;

declare
  v_sql varchar2(200);
  type perm_type is table of varchar2(100);
  v_perm perm_type;
  type user_type is table of varchar2(100);
  v_user user_type;
begin
  v_user := user_type(&user_list);
  v_perm := perm_type(&perm_list);
  for i in 1 .. v_user.count LOOP
    for b in 1 .. v_perm.count loop
      v_sql := 'grant ' || v_perm(b) || ' to ' || v_user(i);
      dbms_output.put_line(v_sql);
      execute immediate v_sql;
    end loop;
  end loop;
end;
/

undefine user_list;
undefine perm_list;