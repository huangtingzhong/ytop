-- File Name: lock_by_object.sql
-- Purpose: MySQL Show locks held on a database object
-- Created: 20260516  by  huangtingzhong

SELECT
	b.object_schema,
	b.object_name,
	b.index_name,
	b.lock_type,
	b.lock_mode,
	b.lock_status,
	a.trx_id,
	a.trx_state,
	a.trx_started,
	a.trx_tables_in_use,
	a.trx_tables_locked,
	a.trx_rows_modified,
	a.trx_rows_locked,
	trx_isolation_level,
	trx_unique_checks
FROM
	information_schema.innodb_trx a
	RIGHT JOIN performance_schema.data_locks b ON a.trx_id = b.engine_transaction_id
WHERE
	b.object_name = 'htz';