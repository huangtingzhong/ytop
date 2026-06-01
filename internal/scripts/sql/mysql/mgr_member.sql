-- File Name: mgr_member.sql
-- Purpose: MySQL Show MySQL Group Replication members
-- Created: 20260516  by  huangtingzhong

select * from performance_schema.replication_group_members;
select * from performance_schema.replication_group_member_stats\G;
select * from performance_schema.replication_connection_status\G;
select * from performance_schema.replication_applier_status_by_worker\G;