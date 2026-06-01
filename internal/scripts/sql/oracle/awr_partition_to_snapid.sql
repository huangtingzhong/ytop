-- File Name: awr_partition_to_snapid.sql
-- Purpose: Oracle AWR Partition To Snapid
-- Created: 20260516  by  huangtingzhong

set serveroutput on lines 200
declare 
CURSOR cur_part IS 
SELECT partition_name from dba_tab_partitions 
WHERE table_name = 'WRH$_ACTIVE_SESSION_HISTORY'; 

query1 varchar2(200); 
query2 varchar2(200); 

TYPE partrec IS RECORD (snapid number, dbid number); 
TYPE partlist IS TABLE OF partrec; 

Outlist partlist; 
begin 
dbms_output.put_line('PARTITION NAME SNAP_ID DBID'); 
dbms_output.put_line('--------------------------- ------- ----------'); 

for part in cur_part loop 
query1 := 'select min(snap_id), dbid from sys.WRH$_ACTIVE_SESSION_HISTORY partition ('||part.partition_name||') group by dbid'; 
execute immediate query1 bulk collect into OutList; 

if OutList.count > 0 then 
for i in OutList.first..OutList.last loop 
dbms_output.put_line(part.partition_name||' Min '||OutList(i).snapid||' '||OutList(i).dbid); 
end loop; 
end if; 

query2 := 'select max(snap_id), dbid from sys.WRH$_ACTIVE_SESSION_HISTORY partition ('||part.partition_name||') group by dbid'; 
execute immediate query2 bulk collect into OutList; 

if OutList.count > 0 then 
for i in OutList.first..OutList.last loop 
dbms_output.put_line(part.partition_name||' Max '||OutList(i).snapid||' '||OutList(i).dbid); 
dbms_output.put_line('---'); 
end loop; 
end if; 

end loop; 
end; 
/