-- File Name: mgr_stat.sql
-- Purpose: MySQL Show MySQL Group Replication status
-- Created: 20260516  by  huangtingzhong

SELECT
	a.channel_name,
	a.member_id,
	concat(
		b.member_host, ":", b.member_port
	) HOST,
	b.member_state,
	b.member_role,
	count_transactions_in_queue AS 'conflict_queue',
	count_transactions_checked AS 'fin_conflic',
	count_conflicts_detected AS 'faild_conflict',
	count_transactions_rows_validating AS 'rows_validating',
	COUNT_TRANSACTIONS_REMOTE_IN_APPLIER_QUEUE AS 'remote_app_queue',
	count_transactions_remote_applied AS 'remote_applied',
	count_transactions_local_proposed AS 'local_proposed',
	count_transactions_local_rollback AS 'local_rollback',
	(
		COUNT_TRANSACTIONS_REMOTE_IN_APPLIER_QUEUE + count_transactions_remote_applied + count_transactions_local_proposed + count_transactions_local_rollback
	) AS 'total'
FROM
	performance_schema.replication_group_member_stats a,
	performance_schema.replication_group_members b
WHERE
	a.member_id = b.member_id
	AND a.channel_name = b.channel_name;
