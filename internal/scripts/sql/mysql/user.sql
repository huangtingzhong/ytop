-- File Name: user.sql
-- Purpose: MySQL User account and privilege overview (&username empty = all users)
-- Created: 20260525  by  huangtingzhong

SELECT '=== Account summary (mysql.user) ===' AS section;

SELECT
    user,
    host,
    account_locked,
    password_expired,
    password_last_changed,
    password_lifetime,
    plugin,
    ssl_type,
    max_questions,
    max_updates,
    max_connections,
    max_user_connections
FROM mysql.user
WHERE ('&username' = '' OR user = '&username')
ORDER BY user, host;

SELECT '=== SHOW GRANTS commands (copy and run if needed) ===' AS section;

SELECT CONCAT('SHOW GRANTS FOR ''', user, '''@''', host, ''';') AS show_grants_cmd
FROM mysql.user
WHERE ('&username' = '' OR user = '&username')
ORDER BY user, host;

SELECT '=== Database-level privileges (mysql.db) ===' AS section;

SELECT
    user,
    host,
    db,
    select_priv,
    insert_priv,
    update_priv,
    delete_priv,
    create_priv,
    drop_priv,
    grant_priv,
    references_priv,
    index_priv,
    alter_priv,
    create_tmp_table_priv,
    lock_tables_priv,
    create_view_priv,
    show_view_priv,
    create_routine_priv,
    alter_routine_priv,
    execute_priv,
    event_priv,
    trigger_priv
FROM mysql.db
WHERE ('&username' = '' OR user = '&username')
ORDER BY user, host, db;

SELECT '=== Global privileges (information_schema.user_privileges) ===' AS section;

SELECT
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.user_privileges
WHERE ('&username' = '' OR grantee LIKE CONCAT('''', '&username', '''@''%'))
ORDER BY grantee, privilege_type;

SELECT '=== Schema privileges (information_schema.schema_privileges) ===' AS section;

SELECT
    grantee,
    table_schema,
    privilege_type,
    is_grantable
FROM information_schema.schema_privileges
WHERE ('&username' = '' OR grantee LIKE CONCAT('''', '&username', '''@''%'))
ORDER BY grantee, table_schema, privilege_type;

SELECT '=== Table privileges (information_schema.table_privileges) ===' AS section;

SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type,
    is_grantable
FROM information_schema.table_privileges
WHERE ('&username' = '' OR grantee LIKE CONCAT('''', '&username', '''@''%'))
ORDER BY grantee, table_schema, table_name, privilege_type;

SELECT '=== Column privileges (information_schema.column_privileges) ===' AS section;

SELECT
    grantee,
    table_schema,
    table_name,
    column_name,
    privilege_type,
    is_grantable
FROM information_schema.column_privileges
WHERE ('&username' = '' OR grantee LIKE CONCAT('''', '&username', '''@''%'))
ORDER BY grantee, table_schema, table_name, column_name, privilege_type;
