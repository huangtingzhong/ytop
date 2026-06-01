-- File Name: mdl_block.sql
-- Purpose: MySQL Show metadata lock blocking sessions
-- Created: 20260516  by  huangtingzhong

--SELECT
--	CONCAT(locked_schema, ':', locked_table) AS lock_schem_table,
--	locked_type,
--	CONCAT_WS(':', waiting_user, waiting_host) waiting_user,
--	waiting_processlist_id as waiting_pid,
--	waiting_age,
--	waiting_state,
--	CONCAT_WS(
--		':', blocking_user, blocking_host
--	) blocking_user,
--	blocking_name,
--	blocking_processlist_id AS block_pid,
--	blocking_age,
--	sql_kill_blocking_connection AS kill_sql,
--	substr(waiting_query, 1,30) AS waiting_query,
--	substr(
--		substring_index(
--			sql_text, "transaction_begin;",-1
--		),
--		1,30
--	) AS blocking_query
--FROM
--	(
--		SELECT
--			b.OWNER_THREAD_ID AS granted_thread_id,
--			a.OBJECT_SCHEMA AS locked_schema,
--			a.OBJECT_NAME AS locked_table,
--			"Metadata Lock" AS locked_type,
--			c.PROCESSLIST_ID AS waiting_processlist_id,
--			c.PROCESSLIST_TIME AS waiting_age,
--			c.PROCESSLIST_INFO AS waiting_query,
--			c.PROCESSLIST_STATE AS waiting_state,
--			c.processlist_user AS waiting_user,
--			c.processlist_host AS waiting_host,
--			d.name as blocking_name,
--			d.PROCESSLIST_ID AS blocking_processlist_id,
--			d.PROCESSLIST_TIME AS blocking_age,
--			d.PROCESSLIST_INFO AS blocking_query,
--			d.processlist_user AS blocking_user,
--			d.processlist_host AS blocking_host,
--			concat('KILL ', d.PROCESSLIST_ID) AS sql_kill_blocking_connection
--		FROM
--			performance_schema.metadata_locks a
--			JOIN performance_schema.metadata_locks b ON a.OBJECT_SCHEMA = b.OBJECT_SCHEMA
--			AND a.OBJECT_NAME = b.OBJECT_NAME
--			AND a.lock_status = 'PENDING'
--			AND b.lock_status = 'GRANTED'
--			AND a.OWNER_THREAD_ID <> b.OWNER_THREAD_ID
--			AND a.lock_type IN ('EXCLUSIVE', 'SHARED_READ_ONLY','SHARED_WRITE')
--			JOIN performance_schema.threads c ON a.OWNER_THREAD_ID = c.THREAD_ID
--			JOIN performance_schema.threads d ON b.OWNER_THREAD_ID = d.THREAD_ID
--	) t1,
--	(
--		SELECT
--			thread_id,
--			group_concat(
--				CASE WHEN EVENT_NAME = 'statement/sql/begin' THEN "transaction_begin" ELSE sql_text END
--				ORDER BY
--					event_id SEPARATOR ";"
--			) AS sql_text
--		FROM
--			performance_schema.events_statements_history
--		GROUP BY
--			thread_id
--	) t2
--WHERE
--	t1.granted_thread_id = t2.thread_id;

--No lock-type filter below; verify background thread before KILL.

--Also query sys.schema_table_lock_waits
--Requires performance_schema.metadata_lock (manual on 5.7, default on 8.0)
--[mysqld]
--performance-schema-instrument='wait/lock/metadata/sql/mdl=ON'
--[mysqld]
--performance-schema-instrument='wait/lock/metadata/sql/mdl=OFF'
--enable online
--UPDATE performance_schema.setup_instruments
--SET ENABLED = 'YES', TIMED = 'YES'
--WHERE NAME = 'wait/lock/metadata/sql/mdl';
--UPDATE performance_schema.setup_instruments
--SET ENABLED = 'NO', TIMED = 'NO'
--WHERE NAME = 'wait/lock/metadata/sql/mdl';

SELECT
	CONCAT(locked_schema, ':', locked_table) AS lock_schem_table,
	waiting_type,
	CONCAT_WS(':', waiting_user, waiting_host) waiting_user,
	waiting_processlist_id as waiting_pid,
	waiting_age,
	waiting_state,
	CONCAT_WS(
		':', blocking_user, blocking_host
	) blocking_user,
	blocking_type,
	blocking_name,
	blocking_processlist_id AS block_pid,
	blocking_age,
	sql_kill_blocking_connection AS kill_sql,
	substr(waiting_query, 1,30) AS waiting_query,
	substr(
		substring_index(
			sql_text, "transaction_begin;",-1
		),
		1,30
	) AS blocking_query
FROM
	(
		SELECT
			b.OWNER_THREAD_ID AS granted_thread_id,
			a.OBJECT_SCHEMA AS locked_schema,
			a.OBJECT_NAME AS locked_table,
			a.lock_type   as waiting_type,
			c.PROCESSLIST_ID AS waiting_processlist_id,
			c.PROCESSLIST_TIME AS waiting_age,
			c.PROCESSLIST_INFO AS waiting_query,
			c.PROCESSLIST_STATE AS waiting_state,
			c.processlist_user AS waiting_user,
			c.processlist_host AS waiting_host,
			d.name as blocking_name,
			b.lock_type as blocking_type,
			d.PROCESSLIST_ID AS blocking_processlist_id,
			d.PROCESSLIST_TIME AS blocking_age,
			d.PROCESSLIST_INFO AS blocking_query,
			d.processlist_user AS blocking_user,
			d.processlist_host AS blocking_host,
			concat('KILL ', d.PROCESSLIST_ID) AS sql_kill_blocking_connection
		FROM
			performance_schema.metadata_locks a
			JOIN performance_schema.metadata_locks b ON a.OBJECT_SCHEMA = b.OBJECT_SCHEMA
			AND a.OBJECT_NAME = b.OBJECT_NAME
			AND a.lock_status = 'PENDING'
			AND b.lock_status = 'GRANTED'
			AND a.OWNER_THREAD_ID <> b.OWNER_THREAD_ID
			JOIN performance_schema.threads c ON a.OWNER_THREAD_ID = c.THREAD_ID
			JOIN performance_schema.threads d ON b.OWNER_THREAD_ID = d.THREAD_ID
	) t1,
	(
		SELECT
			thread_id,
			group_concat(
				CASE WHEN EVENT_NAME = 'statement/sql/begin' THEN "transaction_begin" ELSE sql_text END
				ORDER BY
					event_id SEPARATOR ";"
			) AS sql_text
		FROM
			performance_schema.events_statements_history
		GROUP BY
			thread_id
	) t2
WHERE
	t1.granted_thread_id = t2.thread_id;
