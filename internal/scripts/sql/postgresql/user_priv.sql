-- File Name: user_priv.sql
-- Purpose: PostgreSQL User privileges
-- Created: 20260516  by  huangtingzhong

\prompt 'Please input user name (leave empty to show all users): ' username

-- 1. Database User Information (from pg_roles)
\echo '=== DATABASE USER INFORMATION ==='
SELECT 
    'DB User' as type,
    rolname as user,
    rolsuper as super,
    rolcreaterole as create_role,
    rolcreatedb as create_db,
    rolcanlogin as login,
    rolreplication as replicate,
    rolconnlimit as conn_limit,
    rolvaliduntil as expires
FROM pg_roles 
WHERE CASE 
    WHEN :'username' = '' THEN true
    ELSE rolname = :'username'
END
ORDER BY rolname;

-- 5. Database Role Memberships
\echo ''
\echo '=== ROLE MEMBERSHIPS ==='
SELECT 
    'Role' as type,
    r.rolname as role,
    r.rolsuper as super,
    r.rolcreaterole as create_role,
    r.rolcreatedb as create_db,
    r.rolcanlogin as login
FROM pg_roles r
WHERE CASE 
    WHEN :'username' = '' THEN true
    ELSE r.rolname = :'username'
END
ORDER BY r.rolname;


-- 3. Database Object Permissions (Tables)
\echo ''
\echo '=== TABLE PERMISSIONS ==='
SELECT 
    'Table' as type,
    t.grantee as user,
    t.table_name as table,
    t.privilege_type as privilege,
    t.is_grantable as grantable,
    t.grantor
FROM information_schema.table_privileges t
WHERE CASE 
    WHEN :'username' = '' THEN true
    ELSE t.grantee = :'username'
END
ORDER BY t.grantee, t.table_name, t.privilege_type;

-- 4. Column Permissions
\echo ''
\echo '=== COLUMN PERMISSIONS ==='
SELECT 
    'Column' as type,
    c.grantee as user,
    c.table_name as table,
    c.column_name as column,
    c.privilege_type as privilege,
    c.is_grantable as grantable
FROM information_schema.column_privileges c
WHERE CASE 
    WHEN :'username' = '' THEN true
    ELSE c.grantee = :'username'
END
ORDER BY c.grantee, c.table_name, c.column_name, c.privilege_type;



-- 6. Schema Permissions
\echo ''
\echo '=== SCHEMA PERMISSIONS ==='
SELECT 
    'Schema' as type,
    n.nspname as schema,
    r.rolname as user,
    CASE 
        WHEN has_schema_privilege(r.rolname, n.nspname, 'CREATE') THEN 'CREATE'
        WHEN has_schema_privilege(r.rolname, n.nspname, 'USAGE') THEN 'USAGE'
        ELSE 'NONE'
    END as privilege
FROM pg_namespace n
CROSS JOIN pg_roles r
WHERE CASE 
    WHEN :'username' = '' THEN r.rolcanlogin = true
    ELSE r.rolname = :'username'
END
AND (has_schema_privilege(r.rolname, n.nspname, 'CREATE') OR has_schema_privilege(r.rolname, n.nspname, 'USAGE'))
AND n.nspname NOT LIKE 'pg_%'
AND n.nspname != 'information_schema'
ORDER BY r.rolname, n.nspname;

-- 7. Function Permissions
\echo ''
\echo '=== FUNCTION PERMISSIONS ==='
SELECT 
    'Function' as type,
    f.grantee as user,
    f.routine_name as function,
    f.routine_schema as schema,
    f.privilege_type as privilege,
    f.is_grantable as grantable
FROM information_schema.routine_privileges f
WHERE CASE 
    WHEN :'username' = '' THEN true
    ELSE f.grantee = :'username'
END
ORDER BY f.grantee, f.routine_schema, f.routine_name, f.privilege_type;

-- 8. Usage Statistics
\echo ''
\echo '=== QUERY STATISTICS ==='
SELECT 
    'Stats' as type,
    CASE 
        WHEN :'username' = '' THEN 'All Users'
        ELSE :'username'
    END as target,
    (SELECT count(*) FROM pg_roles WHERE CASE WHEN :'username' = '' THEN true ELSE rolname = :'username' END) as db_users,
    (SELECT count(*) FROM user_permissions WHERE CASE WHEN :'username' = '' THEN true ELSE username = :'username' END) as app_users,
    (SELECT count(*) FROM information_schema.table_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END) as table_perms,
    (SELECT count(*) FROM information_schema.column_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END) as column_perms,
    (SELECT count(*) FROM (
        SELECT DISTINCT r.rolname, n.nspname
        FROM pg_namespace n
        CROSS JOIN pg_roles r
        WHERE CASE 
            WHEN :'username' = '' THEN r.rolcanlogin = true
            ELSE r.rolname = :'username'
        END
        AND (has_schema_privilege(r.rolname, n.nspname, 'CREATE') OR has_schema_privilege(r.rolname, n.nspname, 'USAGE'))
        AND n.nspname NOT LIKE 'pg_%'
        AND n.nspname != 'information_schema'
    ) schema_perms) as schema_perms,
    (SELECT count(*) FROM information_schema.routine_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END) as function_perms;

-- 9. Summary Report
\echo ''
\echo '=== PERMISSION SUMMARY ==='
WITH permission_summary AS (
    SELECT 'DB Users' as type, count(*) as count FROM pg_roles WHERE CASE WHEN :'username' = '' THEN true ELSE rolname = :'username' END
    UNION ALL
    SELECT 'App Users', count(*) FROM user_permissions WHERE CASE WHEN :'username' = '' THEN true ELSE username = :'username' END
    UNION ALL
    SELECT 'Tables', count(*) FROM information_schema.table_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END
    UNION ALL
    SELECT 'Columns', count(*) FROM information_schema.column_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END
    UNION ALL
    SELECT 'Schemas', count(*) FROM (
        SELECT DISTINCT r.rolname, n.nspname
        FROM pg_namespace n
        CROSS JOIN pg_roles r
        WHERE CASE 
            WHEN :'username' = '' THEN r.rolcanlogin = true
            ELSE r.rolname = :'username'
        END
        AND (has_schema_privilege(r.rolname, n.nspname, 'CREATE') OR has_schema_privilege(r.rolname, n.nspname, 'USAGE'))
        AND n.nspname NOT LIKE 'pg_%'
        AND n.nspname != 'information_schema'
    ) schema_perms
    UNION ALL
    SELECT 'Functions', count(*) FROM information_schema.routine_privileges WHERE CASE WHEN :'username' = '' THEN true ELSE grantee = :'username' END
)
SELECT 
    'Summary' as type,
    type as permission_type,
    count
FROM permission_summary
WHERE count > 0
ORDER BY permission_type;
