-- File Name: user.sql
-- Purpose: PostgreSQL Show database users and profiles
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
