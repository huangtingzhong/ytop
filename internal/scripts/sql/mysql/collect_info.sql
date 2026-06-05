-- File Name: collect_mysql_replication_info.sql
-- Purpose: Collect MySQL replication and size audit info (MySQL 5.7+ compatible)
-- Created: 20250603  by  huangtingzhong
--
-- Usage: mysql -h<host> -P<port> -u<user> -p < collect_mysql_replication_info.sql > audit.txt
-- Notes:
--   MySQL 8.0-only objects use dynamic SQL fallback on 5.7.
--   Column-sensitive sections probe information_schema.columns before SELECT.

SELECT '========== 1. Version and instance ==========' AS section;
SELECT VERSION() AS mysql_version;
SELECT @@hostname AS hostname, @@port AS port, @@server_id AS server_id, @@server_uuid AS server_uuid;
SELECT @@datadir AS datadir, @@tmpdir AS tmpdir, @@log_bin_basename AS log_bin_basename;

SELECT '--- 1.1 Object/column availability probe ---' AS subsection;
SELECT 'performance_schema.variables_info' AS check_item,
  IF(COUNT(*) > 0, 'YES', 'NO') AS available
FROM information_schema.tables
WHERE table_schema = 'performance_schema' AND table_name = 'variables_info'
UNION ALL
SELECT 'performance_schema.persisted_variables',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'performance_schema' AND table_name = 'persisted_variables'
UNION ALL
SELECT 'information_schema.INNODB_TABLESPACES',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'information_schema' AND table_name = 'INNODB_TABLESPACES'
UNION ALL
SELECT 'information_schema.FILES',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'information_schema' AND table_name = 'FILES'
UNION ALL
SELECT 'performance_schema.file_summary_by_instance',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'performance_schema' AND table_name = 'file_summary_by_instance'
UNION ALL
SELECT 'information_schema.TABLE_CONSTRAINTS',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'information_schema' AND table_name = 'TABLE_CONSTRAINTS'
UNION ALL
SELECT 'information_schema.STATISTICS (PRIMARY)',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.tables
WHERE table_schema = 'information_schema' AND table_name = 'STATISTICS'
UNION ALL
SELECT 'mysql.user.Repl_slave_priv',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.columns
WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'Repl_slave_priv'
UNION ALL
SELECT 'mysql.user.account_locked',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.columns
WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'account_locked'
UNION ALL
SELECT 'mysql.user.password_expired',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.columns
WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'password_expired'
UNION ALL
SELECT 'mysql.user.plugin',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.columns
WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'plugin'
UNION ALL
SELECT 'variables_info.SET_TIME',
  IF(COUNT(*) > 0, 'YES', 'NO')
FROM information_schema.columns
WHERE table_schema = 'performance_schema' AND table_name = 'variables_info' AND column_name = 'SET_TIME';

SELECT '========== 2. Non-default global variables (MySQL 8.0+ PFS) ==========' AS section;
SELECT '--- 2.1 All globals set to non-compiled values ---' AS subsection;
SET @vi_has_set_meta = (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = 'performance_schema'
    AND table_name = 'variables_info'
    AND column_name = 'SET_TIME'
);
SET @non_default_vars_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'performance_schema'
      AND table_name = 'variables_info'
  ) > 0,
  IF(
    @vi_has_set_meta > 0,
    'SELECT vi.VARIABLE_NAME, gv.VARIABLE_VALUE AS current_value, vi.VARIABLE_SOURCE AS set_source, vi.VARIABLE_PATH AS config_path, vi.MIN_VALUE, vi.MAX_VALUE, vi.SET_TIME, vi.SET_USER, vi.SET_HOST FROM performance_schema.variables_info vi INNER JOIN performance_schema.global_variables gv ON gv.VARIABLE_NAME = vi.VARIABLE_NAME WHERE vi.VARIABLE_SOURCE <> ''COMPILED'' ORDER BY vi.VARIABLE_SOURCE, vi.VARIABLE_NAME',
    'SELECT vi.VARIABLE_NAME, gv.VARIABLE_VALUE AS current_value, vi.VARIABLE_SOURCE AS set_source, vi.VARIABLE_PATH AS config_path, vi.MIN_VALUE, vi.MAX_VALUE FROM performance_schema.variables_info vi INNER JOIN performance_schema.global_variables gv ON gv.VARIABLE_NAME = vi.VARIABLE_NAME WHERE vi.VARIABLE_SOURCE <> ''COMPILED'' ORDER BY vi.VARIABLE_SOURCE, vi.VARIABLE_NAME'
  ),
  'SELECT ''Skipped on MySQL 5.7: performance_schema.variables_info requires MySQL 8.0+'' AS notice'
);
PREPARE _collect_stmt FROM @non_default_vars_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '--- 2.2 Persisted variables (mysqld-auto.cnf) ---' AS subsection;
SET @persisted_vars_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'performance_schema'
      AND table_name = 'persisted_variables'
  ) > 0,
  IF(
    (
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = 'performance_schema'
        AND table_name = 'variables_info'
    ) > 0,
    'SELECT pv.VARIABLE_NAME, pv.VARIABLE_VALUE AS persisted_value, gv.VARIABLE_VALUE AS current_value, vi.VARIABLE_SOURCE AS set_source FROM performance_schema.persisted_variables pv LEFT JOIN performance_schema.global_variables gv ON gv.VARIABLE_NAME = pv.VARIABLE_NAME LEFT JOIN performance_schema.variables_info vi ON vi.VARIABLE_NAME = pv.VARIABLE_NAME ORDER BY pv.VARIABLE_NAME',
    'SELECT pv.VARIABLE_NAME, pv.VARIABLE_VALUE AS persisted_value, gv.VARIABLE_VALUE AS current_value FROM performance_schema.persisted_variables pv LEFT JOIN performance_schema.global_variables gv ON gv.VARIABLE_NAME = pv.VARIABLE_NAME ORDER BY pv.VARIABLE_NAME'
  ),
  'SELECT ''Skipped on MySQL 5.7: performance_schema.persisted_variables requires MySQL 8.0+'' AS notice'
);
PREPARE _collect_stmt FROM @persisted_vars_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '--- 2.3 Non-default count by source ---' AS subsection;
SET @non_default_count_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'performance_schema'
      AND table_name = 'variables_info'
  ) > 0,
  'SELECT vi.VARIABLE_SOURCE AS set_source, COUNT(*) AS variable_count FROM performance_schema.variables_info vi WHERE vi.VARIABLE_SOURCE <> ''COMPILED'' GROUP BY vi.VARIABLE_SOURCE ORDER BY variable_count DESC, vi.VARIABLE_SOURCE',
  'SELECT ''Skipped on MySQL 5.7: performance_schema.variables_info requires MySQL 8.0+'' AS notice'
);
PREPARE _collect_stmt FROM @non_default_count_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '========== 3. Replication variables (reference checklist) ==========' AS section;
SHOW VARIABLES WHERE Variable_name IN (
  'server_id', 'server_uuid', 'log_bin', 'log_bin_basename', 'log_bin_index',
  'binlog_format', 'binlog_row_image', 'binlog_checksum', 'sync_binlog',
  'expire_logs_days', 'binlog_expire_logs_seconds', 'binlog_expire_logs_auto_purge', 'max_binlog_size',
  'gtid_mode', 'enforce_gtid_consistency',
  'log_slave_updates', 'log_replica_updates',
  'relay_log', 'relay_log_basename', 'relay_log_index', 'relay_log_recovery',
  'read_only', 'super_read_only',
  'master_info_repository', 'relay_log_info_repository',
  'slave_parallel_workers', 'replica_parallel_workers',
  'slave_parallel_type', 'replica_parallel_type',
  'slave_preserve_commit_order', 'replica_preserve_commit_order',
  'report_host', 'report_port',
  'skip_slave_start', 'skip_replica_start',
  'rpl_semi_sync_master_enabled', 'rpl_semi_sync_slave_enabled',
  'rpl_semi_sync_source_enabled', 'rpl_semi_sync_replica_enabled',
  'bind_address', 'character_set_server', 'collation_server',
  'lower_case_table_names', 'default_storage_engine',
  'innodb_buffer_pool_size', 'innodb_log_file_size',
  'innodb_flush_log_at_trx_commit', 'sync_relay_log',
  'max_connections', 'max_allowed_packet', 'sql_mode',
  'transaction_isolation', 'explicit_defaults_for_timestamp','binlog_transaction_dependency_tracking',
  'transaction_write_set_extraction', 'binlog_transaction_dependency_history_size','binlog_group_commit_sync_delay'
);

SELECT '========== 4. Replication filter rules ==========' AS section;
SHOW VARIABLES WHERE Variable_name LIKE 'binlog\_%' AND Variable_name IN ('binlog_do_db','binlog_ignore_db')
   OR Variable_name LIKE 'replicate\_%';

SELECT '========== 5. Master status ==========' AS section;
SHOW MASTER STATUS;

SELECT '========== 6. Slave/Replica status ==========' AS section;
SHOW SLAVE STATUS\G

SELECT '========== 7. Binlog show commands ==========' AS section;

SELECT '--- 7.1 Binlog retention variables ---' AS subsection;
SHOW VARIABLES WHERE Variable_name IN (
  'expire_logs_days',
  'binlog_expire_logs_seconds',
  'binlog_expire_logs_auto_purge',
  'max_binlog_size',
  'log_bin',
  'log_bin_basename',
  'log_bin_index'
);

SELECT '--- 7.2 SHOW BINARY LOGS (sum File_size for total) ---' AS subsection;
SHOW BINARY LOGS;

SELECT '--- 7.3 SHOW BINLOG EVENTS (current file, LIMIT 10) ---' AS subsection;
SET @binlog_index = LOAD_FILE(@@log_bin_index);
SET @binlog_index = TRIM(BOTH '\n' FROM REPLACE(IFNULL(@binlog_index, ''), CHAR(13), ''));
SET @binlog_file = TRIM(SUBSTRING_INDEX(@binlog_index, CHAR(10), -1));
SET @binlog_events_sql = IF(
  @@log_bin IN ('OFF', '0', 0),
  'SELECT ''log_bin is OFF, skip SHOW BINLOG EVENTS'' AS notice',
  IF(
    @binlog_index = '' OR @binlog_file = '',
    'SELECT ''Cannot read binlog index; check FILE privilege and secure_file_priv'' AS notice',
    CONCAT('SHOW BINLOG EVENTS IN ''', @binlog_file, ''' LIMIT 10')
  )
);
PREPARE _collect_stmt FROM @binlog_events_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '--- 7.4 mysql.binlog_size_snap (if monitor installed) ---' AS subsection;
SET @binlog_snap_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'mysql'
      AND table_name = 'binlog_size_snap'
  ) > 0,
  IF(
    (
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = 'mysql'
        AND table_name = 'binlog_size_snap'
        AND column_name = 'snap_time'
    ) > 0,
    'SELECT snap_time, total_bytes, ROUND(total_bytes / 1024 / 1024 / 1024, 2) AS total_gb, file_count FROM mysql.binlog_size_snap ORDER BY snap_time DESC LIMIT 10',
    'SELECT ''mysql.binlog_size_snap exists but expected columns missing (snap_time/total_bytes/file_count)'' AS notice'
  ),
  'SELECT ''mysql.binlog_size_snap not found; install binlog_size_monitor.sql'' AS notice'
);
PREPARE _collect_stmt FROM @binlog_snap_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '--- 7.5 Binlog I/O (Performance Schema) ---' AS subsection;
SET @binlog_io_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = 'performance_schema'
      AND table_name = 'file_summary_by_instance'
      AND column_name = 'SUM_NUMBER_OF_BYTES_WRITE'
  ) > 0,
  'SELECT SUBSTRING_INDEX(REPLACE(FILE_NAME, ''\\\\'', ''/''), ''/'', -1) AS log_name, SUM_NUMBER_OF_BYTES_WRITE AS bytes_written FROM performance_schema.file_summary_by_instance WHERE REPLACE(FILE_NAME, ''\\\\'', ''/'') LIKE ''%mysql-bin.%'' AND REPLACE(FILE_NAME, ''\\\\'', ''/'') NOT LIKE ''%index%'' ORDER BY FILE_NAME',
  'SELECT ''performance_schema.file_summary_by_instance.SUM_NUMBER_OF_BYTES_WRITE not available'' AS notice'
);
PREPARE _collect_stmt FROM @binlog_io_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '========== 8. GTID ==========' AS section;
SHOW VARIABLES WHERE Variable_name IN ('gtid_mode','enforce_gtid_consistency','gtid_purged');
SELECT @@GLOBAL.gtid_executed AS gtid_executed;

SELECT '========== 9. Business DB size summary ==========' AS section;
SELECT
  COUNT(DISTINCT s.SCHEMA_NAME) AS business_schema_count,
  IFNULL(SUM(t.TABLE_ROWS), 0) AS business_est_rows,
  COUNT(t.TABLE_NAME) AS business_table_count,
  IFNULL(SUM(t.DATA_LENGTH), 0) AS business_data_bytes,
  IFNULL(SUM(t.INDEX_LENGTH), 0) AS business_index_bytes,
  IFNULL(SUM(t.DATA_FREE), 0) AS business_free_bytes,
  IFNULL(SUM(t.DATA_LENGTH + t.INDEX_LENGTH), 0) AS business_total_bytes,
  ROUND(IFNULL(SUM(t.DATA_LENGTH + t.INDEX_LENGTH), 0) / 1024 / 1024, 2) AS business_total_mb
FROM information_schema.SCHEMATA s
LEFT JOIN information_schema.TABLES t
  ON s.SCHEMA_NAME = t.TABLE_SCHEMA AND t.TABLE_TYPE = 'BASE TABLE'
WHERE s.SCHEMA_NAME NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys');

SELECT '========== 10. Business DB size detail ==========' AS section;
SELECT
  s.SCHEMA_NAME,
  s.DEFAULT_CHARACTER_SET_NAME,
  s.DEFAULT_COLLATION_NAME,
  COUNT(t.TABLE_NAME) AS table_count,
  IFNULL(SUM(t.TABLE_ROWS), 0) AS est_rows,
  IFNULL(SUM(t.DATA_LENGTH), 0) AS data_bytes,
  ROUND(IFNULL(SUM(t.DATA_LENGTH), 0) / 1024 / 1024, 2) AS data_mb,
  IFNULL(SUM(t.INDEX_LENGTH), 0) AS index_bytes,
  ROUND(IFNULL(SUM(t.INDEX_LENGTH), 0) / 1024 / 1024, 2) AS index_mb,
  IFNULL(SUM(t.DATA_FREE), 0) AS free_bytes,
  ROUND(IFNULL(SUM(t.DATA_FREE), 0) / 1024 / 1024, 2) AS free_mb,
  IFNULL(SUM(t.DATA_LENGTH + t.INDEX_LENGTH), 0) AS total_bytes,
  ROUND(IFNULL(SUM(t.DATA_LENGTH + t.INDEX_LENGTH), 0) / 1024 / 1024, 2) AS total_mb
FROM information_schema.SCHEMATA s
LEFT JOIN information_schema.TABLES t
  ON s.SCHEMA_NAME = t.TABLE_SCHEMA AND t.TABLE_TYPE = 'BASE TABLE'
WHERE s.SCHEMA_NAME NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY s.SCHEMA_NAME, s.DEFAULT_CHARACTER_SET_NAME, s.DEFAULT_COLLATION_NAME
ORDER BY total_bytes DESC;

SELECT '========== 11. All schema size (incl mysql/sys) ==========' AS section;
SELECT
  TABLE_SCHEMA,
  IFNULL(ENGINE, 'NULL') AS engine,
  COUNT(*) AS table_count,
  IFNULL(SUM(TABLE_ROWS), 0) AS est_rows,
  IFNULL(SUM(DATA_LENGTH), 0) AS data_bytes,
  ROUND(IFNULL(SUM(DATA_LENGTH), 0) / 1024 / 1024, 2) AS data_mb,
  IFNULL(SUM(INDEX_LENGTH), 0) AS index_bytes,
  ROUND(IFNULL(SUM(INDEX_LENGTH), 0) / 1024 / 1024, 2) AS index_mb,
  IFNULL(SUM(DATA_FREE), 0) AS free_bytes,
  IFNULL(SUM(DATA_LENGTH + INDEX_LENGTH), 0) AS total_bytes,
  ROUND(IFNULL(SUM(DATA_LENGTH + INDEX_LENGTH), 0) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema')
  AND TABLE_TYPE = 'BASE TABLE'
GROUP BY TABLE_SCHEMA, ENGINE
ORDER BY total_bytes DESC, TABLE_SCHEMA, engine;

SELECT '========== 12. Top 50 largest tables ==========' AS section;
SELECT
  TABLE_SCHEMA,
  TABLE_NAME,
  ENGINE,
  IFNULL(TABLE_ROWS, 0) AS est_rows,
  IFNULL(DATA_LENGTH, 0) AS data_bytes,
  ROUND(IFNULL(DATA_LENGTH, 0) / 1024 / 1024, 2) AS data_mb,
  IFNULL(INDEX_LENGTH, 0) AS index_bytes,
  ROUND(IFNULL(INDEX_LENGTH, 0) / 1024 / 1024, 2) AS index_mb,
  IFNULL(DATA_FREE, 0) AS free_bytes,
  IFNULL(DATA_LENGTH + INDEX_LENGTH, 0) AS total_bytes,
  ROUND(IFNULL(DATA_LENGTH + INDEX_LENGTH, 0) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY total_bytes DESC
LIMIT 50;

SELECT '========== 13. InnoDB tablespaces / files ==========' AS section;
SET @innodb_space_sql = IF(
  (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = 'information_schema'
      AND table_name = 'INNODB_TABLESPACES'
      AND column_name = 'FILE_SIZE'
  ) > 0,
  'SELECT IFNULL(SUM(FILE_SIZE), 0) AS file_size_bytes, ROUND(IFNULL(SUM(FILE_SIZE), 0) / 1024 / 1024, 2) AS file_size_mb, IFNULL(SUM(ALLOCATED_SIZE), 0) AS allocated_bytes, ROUND(IFNULL(SUM(ALLOCATED_SIZE), 0) / 1024 / 1024, 2) AS allocated_mb, COUNT(*) AS space_count, ''INNODB_TABLESPACES (8.0+)'' AS source_view FROM information_schema.INNODB_TABLESPACES',
  IF(
    (
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = 'information_schema'
        AND table_name = 'FILES'
        AND column_name = 'TOTAL_EXTENTS'
    ) > 0,
    'SELECT IFNULL(SUM(TOTAL_EXTENTS * IFNULL(EXTENT_SIZE, 1048576)), 0) AS file_size_bytes, ROUND(IFNULL(SUM(TOTAL_EXTENTS * IFNULL(EXTENT_SIZE, 1048576)), 0) / 1024 / 1024, 2) AS file_size_mb, IFNULL(SUM(FREE_EXTENTS * IFNULL(EXTENT_SIZE, 1048576)), 0) AS free_file_bytes, ROUND(IFNULL(SUM(FREE_EXTENTS * IFNULL(EXTENT_SIZE, 1048576)), 0) / 1024 / 1024, 2) AS free_file_mb, COUNT(*) AS space_count, ''FILES (5.7)'' AS source_view FROM information_schema.FILES WHERE FILE_TYPE = ''TABLESPACE'' AND TABLESPACE_NAME IS NOT NULL',
    'SELECT ''Neither INNODB_TABLESPACES nor FILES.TOTAL_EXTENTS available'' AS notice'
  )
);
PREPARE _collect_stmt FROM @innodb_space_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '--- 13.1 InnoDB DATA_FREE (information_schema.TABLES) ---' AS subsection;
SELECT
  IFNULL(SUM(DATA_FREE), 0) AS data_free_bytes,
  ROUND(IFNULL(SUM(DATA_FREE), 0) / 1024 / 1024, 2) AS data_free_mb
FROM information_schema.TABLES
WHERE ENGINE = 'InnoDB'
  AND TABLE_TYPE = 'BASE TABLE';

SELECT '========== 14. Storage engine distribution ==========' AS section;
SELECT
  IFNULL(ENGINE, 'NULL') AS engine,
  COUNT(*) AS table_count,
  IFNULL(SUM(DATA_LENGTH), 0) AS data_bytes,
  IFNULL(SUM(INDEX_LENGTH), 0) AS index_bytes,
  IFNULL(SUM(DATA_LENGTH + INDEX_LENGTH), 0) AS total_bytes,
  ROUND(IFNULL(SUM(DATA_LENGTH + INDEX_LENGTH), 0) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND TABLE_TYPE = 'BASE TABLE'
GROUP BY ENGINE
ORDER BY total_bytes DESC;

SELECT '========== 15. Non-InnoDB tables (top 200) ==========' AS section;
SELECT TABLE_SCHEMA, TABLE_NAME, ENGINE,
  IFNULL(DATA_LENGTH + INDEX_LENGTH, 0) AS total_bytes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND TABLE_TYPE = 'BASE TABLE'
  AND (ENGINE IS NULL OR ENGINE <> 'InnoDB')
ORDER BY total_bytes DESC
LIMIT 200;

SELECT '========== 16. Tables without primary key ==========' AS section;

SELECT '--- 16.1 Count by schema ---' AS subsection;
SELECT
  t.TABLE_SCHEMA,
  COUNT(*) AS no_pk_table_count
FROM information_schema.TABLES t
WHERE t.TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND t.TABLE_TYPE = 'BASE TABLE'
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS s
    WHERE s.TABLE_SCHEMA = t.TABLE_SCHEMA
      AND s.TABLE_NAME = t.TABLE_NAME
      AND s.INDEX_NAME = 'PRIMARY'
  )
GROUP BY t.TABLE_SCHEMA
ORDER BY no_pk_table_count DESC, t.TABLE_SCHEMA;

SELECT '--- 16.2 Table list ---' AS subsection;
SELECT
  t.TABLE_SCHEMA,
  t.TABLE_NAME,
  t.ENGINE,
  IFNULL(t.TABLE_ROWS, 0) AS est_rows,
  IFNULL(t.DATA_LENGTH, 0) AS data_bytes,
  ROUND(IFNULL(t.DATA_LENGTH, 0) / 1024 / 1024, 2) AS data_mb,
  IFNULL(t.INDEX_LENGTH, 0) AS index_bytes,
  IFNULL(t.DATA_LENGTH + t.INDEX_LENGTH, 0) AS total_bytes,
  ROUND(IFNULL(t.DATA_LENGTH + t.INDEX_LENGTH, 0) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES t
WHERE t.TABLE_SCHEMA NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
  AND t.TABLE_TYPE = 'BASE TABLE'
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.STATISTICS s
    WHERE s.TABLE_SCHEMA = t.TABLE_SCHEMA
      AND s.TABLE_NAME = t.TABLE_NAME
      AND s.INDEX_NAME = 'PRIMARY'
  )
ORDER BY total_bytes DESC, t.TABLE_SCHEMA, t.TABLE_NAME;

SELECT '========== 17. Replication users ==========' AS section;
SET @has_repl_slave_priv = (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'Repl_slave_priv'
);
SET @has_account_locked = (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'account_locked'
);
SET @has_password_expired = (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'password_expired'
);
SET @has_plugin = (
  SELECT COUNT(*)
  FROM information_schema.columns
  WHERE table_schema = 'mysql' AND table_name = 'user' AND column_name = 'plugin'
);
SET @repl_users_sql = IF(
  @has_repl_slave_priv = 0,
  'SELECT ''mysql.user.Repl_slave_priv column not available on this server'' AS notice',
  IF(
    @has_account_locked > 0 AND @has_password_expired > 0 AND @has_plugin > 0,
    'SELECT CONCAT(user, ''@'', host) AS account, Repl_slave_priv, Repl_client_priv, Super_priv, Reload_priv, account_locked, password_expired, plugin FROM mysql.user ORDER BY user, host',
    IF(
      @has_password_expired > 0 AND @has_plugin > 0,
      'SELECT CONCAT(user, ''@'', host) AS account, Repl_slave_priv, Repl_client_priv, Super_priv, Reload_priv, password_expired, plugin FROM mysql.user ORDER BY user, host',
      IF(
        @has_plugin > 0,
        'SELECT CONCAT(user, ''@'', host) AS account, Repl_slave_priv, Repl_client_priv, Super_priv, Reload_priv, plugin FROM mysql.user ORDER BY user, host',
        'SELECT CONCAT(user, ''@'', host) AS account, Repl_slave_priv, Repl_client_priv, Super_priv, Reload_priv FROM mysql.user ORDER BY user, host'
      )
    )
  )
);
PREPARE _collect_stmt FROM @repl_users_sql;
EXECUTE _collect_stmt;
DEALLOCATE PREPARE _collect_stmt;

SELECT '========== 18. Replication status metrics ==========' AS section;
SHOW GLOBAL STATUS WHERE Variable_name IN (
  'Uptime', 'Threads_connected', 'Threads_running',
  'Binlog_cache_disk_use', 'Binlog_cache_use',
  'Com_show_master_status', 'Com_show_slave_status',
  'Slave_running', 'Slave_retried_transactions',
  'Rpl_semi_sync_master_status', 'Rpl_semi_sync_slave_status'
);
