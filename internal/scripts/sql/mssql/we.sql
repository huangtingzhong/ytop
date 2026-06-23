-- File Name: we.sql
-- Purpose: MSSQL Active sessions and waits
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i we.sql -w 300 -W
-- MinVersion: 2008
-- Variables:
--   &login  login name (empty = all)
--   &spid   session id (empty = all active)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaProcess
-- Oracle ref: we.sql
--
SET NOCOUNT ON;

-- COL: spid a6 login a14 host a14 program a20 status a8 wait a18 blk a6 elapsed a8 db a15 (~280)
PRINT '---------- active sessions ----------';
SELECT
    RIGHT('      ' + CAST(s.session_id AS VARCHAR(6)), 6) AS spid,
    LEFT(ISNULL(s.login_name, ''), 14) AS login,
    LEFT(ISNULL(s.host_name, ''), 14) AS host,
    LEFT(ISNULL(s.program_name, ''), 20) AS program,
    LEFT(s.status, 8) AS status,
    LEFT(ISNULL(r.wait_type, ''), 18) AS wait,
    RIGHT('    ' + CAST(ISNULL(r.blocking_session_id, 0) AS VARCHAR(6)), 6) AS blocker,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000 AS VARCHAR(8)) AS elapsed_s,
    LEFT(ISNULL(DB_NAME(r.database_id), ''), 15) AS dbname
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
WHERE s.is_user_process = 1
  AND (s.status <> 'sleeping' OR r.session_id IS NOT NULL)
  AND ('&login' = '' OR s.login_name = '&login')
  AND ('&spid' = '' OR CAST(s.session_id AS VARCHAR(10)) = '&spid')
ORDER BY ISNULL(r.total_elapsed_time, 0) DESC, s.session_id;

PRINT '---------- sleeping user sessions (count) ----------';
SELECT COUNT(*) AS sleeping_sessions
FROM sys.dm_exec_sessions
WHERE is_user_process = 1 AND status = 'sleeping';
