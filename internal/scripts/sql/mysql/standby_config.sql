-- File Name: standby_config.sql
-- Purpose: MySQL Show standby replication configuration
-- Created: 20260516  by  huangtingzhong

#from mysql.8.0
#created by htz   2000823
select * from performance_schema.replication_connection_configuration\G;
select * from mysql.slave_master_info\G;
select * from mysql.slave_relay_log_info\G;
select * from mysql.slave_worker_info\G;
show slave status\G;