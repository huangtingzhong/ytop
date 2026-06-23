-- File Name: ag_login_cmp.sql
-- Purpose: MSSQL Compare logins across AG replicas (read)
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i ag_login_cmp.sql -w 300 -W
-- dbatools: Compare-DbaAgReplicaLogin
--
SET NOCOUNT ON;

PRINT 'Run Compare-DbaAgReplicaLogin via dbatools on control host; SQL template lists local logins';
SELECT name, type_desc, create_date FROM sys.server_principals WHERE type IN ('S','U') ORDER BY name;
