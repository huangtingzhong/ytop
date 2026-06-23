-- File Name: ag_suspend.sql
-- Purpose: MSSQL Suspend AG data movement (CHANGE)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_suspend.sql -w 300 -W
--
-- Variables:
--   &ag_name  AG name
--   &dbname  database name
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Suspend-DbaAgDbDataMovement
--
SET NOCOUNT ON;
-- *** P2 CHANGE SCRIPT - requires confirmation before use ***

PRINT 'Template only - ALTER DATABASE ... SET HADR SUSPEND after confirmation';
