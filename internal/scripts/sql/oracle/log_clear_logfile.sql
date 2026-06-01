-- File Name: log_clear_logfile.sql
-- Purpose: Oracle Log Clear Logfile
-- Created: 20260516  by  huangtingzhong

set serveroutput on;
begin
for log_cur in ( select group# group_no from v$log )
loop
execute immediate 'alter database clear logfile group '||log_cur.group_no;
end loop;
end;
/

begin
for log_cur in ( select group# group_no from v$standby_log )
loop
execute immediate 'alter database clear logfile group '||log_cur.group_no;
end loop;
end;
/
 
