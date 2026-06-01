-- File Name: lock_innodb.sql
-- Purpose: MySQL Show InnoDB lock holders and waiters
-- Created: 20260516  by  huangtingzhong

SELECT
	CONCAT_WS(
		':',
		IFNULL(b.object_schema, "NULL"),
		IFNULL(b.object_name, "NULL"),
		IFNULL (b.index_name, "NULL")
	) DB_OBJECT_INDEXNAME,
	b.lock_type,
	b.lock_mode,
	b.lock_status,
    b.lock_data,
	a.trx_id,
	a.trx_state,
	a.trx_started,
	a.trx_tables_in_use,
	a.trx_tables_locked,
	a.trx_rows_modified,
	a.trx_rows_locked,
	trx_isolation_level,
	trx_unique_checks,
	sqltext.sql_text
FROM
	information_schema.innodb_trx a
	RIGHT JOIN performance_schema.data_locks b ON a.trx_id = b.engine_transaction_id,
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
			where event_name not in ('statement/sql/select','statement/sql/set_option')
		GROUP BY
			thread_id
	) sqltext
WHERE
	b.engine = 'INNODB'
	AND b.thread_id = sqltext.thread_id
ORDER BY
	trx_started;
