-- File Name: who.sql
-- Purpose: MSSQL WhoIsActive-style session detail (read)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i who.sql -w 300 -W
-- dbatools: Invoke-DbaWhoIsActive
--
SET NOCOUNT ON;

-- Requires sp_WhoIsActive installed; fallback to dm_exec_* views
SELECT s.session_id, s.login_name, s.host_name, r.status, r.command, r.wait_type,
       LEFT(SUBSTRING(t.text,r.statement_start_offset/2+1,200),200) AS sql_text
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id=r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process=1 ORDER BY s.session_id;
