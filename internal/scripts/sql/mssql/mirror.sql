-- File Name: mirror.sql
-- Purpose: MSSQL Database mirroring status
-- Created: 20260613  by  huangtingzhong
--
-- Usage: sqlcmd -S host -d master -i mirror.sql -w 300 -W
-- MinVersion: 2008 (database_id join; port via tcp_endpoints)
-- Variables:
--   &dbname  database name (empty = all mirrored)
-- ytop: interactive prompt; sqlcmd-only: see Usage
-- dbatools: Get-DbaDbMirror
--
SET NOCOUNT ON;

-- COL: db a20 role a10 partner a22 state a12 safety a10 witness a12 wit_st a10 (~280)
PRINT '---------- database mirroring ----------';
SELECT
    LEFT(d.name, 20) AS dbname,
    LEFT(m.mirroring_role_desc, 10) AS role,
    LEFT(ISNULL(m.mirroring_partner_name, ''), 22) AS partner,
    LEFT(m.mirroring_state_desc, 12) AS state,
    LEFT(m.mirroring_safety_level_desc, 10) AS safety,
    LEFT(ISNULL(m.mirroring_witness_name, ''), 12) AS witness,
    LEFT(ISNULL(m.mirroring_witness_state_desc, ''), 10) AS wit_state
FROM sys.database_mirroring m
JOIN sys.databases d ON m.database_id = d.database_id
WHERE m.mirroring_guid IS NOT NULL
  AND ('&dbname' = '' OR d.name = '&dbname')
ORDER BY d.name;

PRINT '---------- mirroring endpoint ----------';
SELECT LEFT(e.name, 25) AS endpoint, LEFT(e.type_desc, 15) AS type,
       e.state_desc, CAST(ISNULL(t.port, 0) AS VARCHAR(6)) AS port
FROM sys.endpoints e
LEFT JOIN sys.tcp_endpoints t ON e.endpoint_id = t.endpoint_id
WHERE e.type = 4;
