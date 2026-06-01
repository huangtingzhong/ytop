-- File Name: replica_slave.sql
-- Purpose: MySQL Show replication slave status
-- Created: 20260516  by  huangtingzhong

show full processlist;
show slave status\G
select * from performance_schema.replication_applier_filters\G
select * from performance_schema.replication_applier_global_filters\G
select * from performance_schema.replication_applier_status\G
select * from performance_schema.replication_applier_status_by_coordinator\G
select * from performance_schema.replication_applier_status_by_worker\G
select * from performance_schema.replication_asynchronous_connection_failover\G
select * from performance_schema.replication_asynchronous_connection_failover_managed\G
select * from performance_schema.replication_connection_status\G
select * from performance_schema.replication_connection_configuration\G
select * from performance_schema.replication_group_member_stats\G
select * from performance_schema.replication_group_members\G
