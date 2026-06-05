SELECT
	c.id,
	c.user,
	c.host,
	c.db,
	d.trx_started,
	a.SQL_TEXT
FROM
	performance_schema.events_statements_current a
	JOIN performance_schema.threads b ON a.THREAD_ID = b.THREAD_ID
	JOIN information_schema.PROCESSLIST c ON b.PROCESSLIST_ID = c.id
	JOIN information_schema.INNODB_TRX d ON c.id = d.trx_mysql_thread_id
ORDER BY
	d.trx_started
;