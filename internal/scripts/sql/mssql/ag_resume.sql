-- File Name: ag_resume.sql
-- Purpose: MSSQL Resume AG data movement (CHANGE)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_resume.sql -w 300 -W
--
-- Variables:
--   &ag_name  AG name
--   &dbname  database name
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Resume-DbaAgDbDataMovement
--
SET NOCOUNT ON;
-- *** P2 CHANGE SCRIPT - requires confirmation before use ***

PRINT 'Template only - ALTER DATABASE ... SET HADR RESUME after confirmation';
