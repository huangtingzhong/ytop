-- File Name: awr_mmon_10046_enable.sql
-- Purpose: Oracle AWR Mmon 10046 Enable
-- Created: 20260516  by  huangtingzhong

begin 
dbms_monitor.serv_mod_act_trace_enable(service_name=>'SYS$BACKGROUND', 
module_name=>'MMON_SLAVE', 
action_name=>'Auto-Flush Slave Action'); 

dbms_monitor.serv_mod_act_trace_enable(service_name=>'SYS$BACKGROUND', 
module_name=>'MMON_SLAVE', 
action_name=>'Remote-Flush Slave Action'); 
end; 
/
