-- File Name: lock.sql
-- Purpose: PostgreSQL Lock
-- Created: 20260516  by  huangtingzhong

\prompt 'please input pid: '  pid
SELECT 
    l.locktype,
    d.datname AS database_name,
    l.relation::regclass,
    l.page,
    l.tuple,
    l.virtualxid,
    l.transactionid,
    l.classid,
    l.objid,
    l.objsubid,
    l.virtualtransaction,
    l.pid,
    l.mode,
    l.granted
FROM pg_locks l
LEFT JOIN pg_database d ON l.database = d.oid
WHERE l.pid != pg_backend_pid() 
  AND l.pid = COALESCE(:pid, l.pid)
ORDER BY l.pid, l.locktype;
