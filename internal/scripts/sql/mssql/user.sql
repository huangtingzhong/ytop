-- File Name: user.sql
-- Purpose: MSSQL login and database user mapping across all online databases
-- Created: 20260613  by  huangtingzhong
--
-- Usage: ytop -f user.sql
--        sqlcmd -S host -d master -i user.sql -w 300 -W
--
--
SET NOCOUNT ON;

DECLARE @login SYSNAME;
SET @login = N'&login';

DECLARE @db SYSNAME;
DECLARE @piece NVARCHAR(MAX);
DECLARE @union NVARCHAR(MAX) = N'';
DECLARE @mapped NVARCHAR(MAX) = N'';
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state_desc = N'ONLINE'
      AND HAS_DBACCESS(name) = 1
    ORDER BY name;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @piece = N'
SELECT
    LEFT(sp.name, 30) AS login_name,
    LEFT(sp.type_desc, 20) AS login_type,
    CASE sp.is_disabled WHEN 1 THEN ''DISABLED'' ELSE ''ENABLED'' END AS login_status,
    N''' + REPLACE(@db, N'''', N'''''') + N''' AS database_name,
    LEFT(dp.name, 30) AS db_user_name,
    LEFT(dp.type_desc, 20) AS db_user_type,
    CAST(N''MAPPED'' AS VARCHAR(12)) AS map_type
FROM sys.server_principals sp
INNER JOIN [' + REPLACE(@db, N']', N']]') + N'].sys.database_principals dp ON dp.sid = sp.sid
WHERE sp.type IN (N''S'', N''U'', N''G'')
  AND sp.name NOT LIKE N''##%''
  AND dp.type IN (N''S'', N''U'', N''G'', N''E'', N''X'')';

    BEGIN TRY
        SET @union = @union + CASE WHEN @union = N'' THEN N'' ELSE N' UNION ALL ' END + @piece;
        SET @mapped = @mapped + CASE WHEN @mapped = N'' THEN N'' ELSE N' UNION ALL ' END
            + N'SELECT LEFT(sp.name, 30) AS login_name
               FROM sys.server_principals sp
               INNER JOIN [' + REPLACE(@db, N']', N']]') + N'].sys.database_principals dp ON dp.sid = sp.sid
               WHERE sp.type IN (N''S'', N''U'', N''G'')
                 AND sp.name NOT LIKE N''##%''
                 AND dp.type IN (N''S'', N''U'', N''G'', N''E'', N''X'')';
    END TRY
    BEGIN CATCH
        PRINT CONCAT(N'SKIP DB (mapped): ', @db, N' - ', ERROR_MESSAGE());
    END CATCH;

    SET @piece = N'
SELECT
    CAST(NULL AS SYSNAME) AS login_name,
    CAST(NULL AS NVARCHAR(60)) AS login_type,
    CAST(NULL AS VARCHAR(10)) AS login_status,
    N''' + REPLACE(@db, N'''', N'''''') + N''' AS database_name,
    LEFT(dp.name, 30) AS db_user_name,
    LEFT(dp.type_desc, 20) AS db_user_type,
    CAST(N''ORPHAN'' AS VARCHAR(12)) AS map_type
FROM [' + REPLACE(@db, N']', N']]') + N'].sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE sp.sid IS NULL
  AND dp.type IN (N''S'', N''U'', N''G'')
  AND dp.name NOT IN (N''dbo'', N''guest'', N''sys'', N''INFORMATION_SCHEMA'')';

    BEGIN TRY
        SET @union = @union + N' UNION ALL ' + @piece;
    END TRY
    BEGIN CATCH
        PRINT CONCAT(N'SKIP DB (orphan): ', @db, N' - ', ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM db_cur INTO @db;
END;

CLOSE db_cur;
DEALLOCATE db_cur;

PRINT N'===== Login <-> Database User mapping =====';

IF @union = N''
BEGIN
    PRINT N'(no accessible online databases)';
END
ELSE
BEGIN
    SET @sql = N'
SELECT
    LEFT(ISNULL(m.login_name, N''(none)''), 30) AS login,
    LEFT(ISNULL(m.login_type, N''''), 20) AS login_type,
    LEFT(ISNULL(m.login_status, N''''), 10) AS login_status,
    LEFT(m.database_name, 30) AS db_name,
    LEFT(m.db_user_name, 30) AS db_user,
    LEFT(ISNULL(m.db_user_type, N''''), 20) AS user_type,
    m.map_type
FROM (' + @union + N') m
WHERE (@login = N'''' OR m.login_name = @login OR m.db_user_name = @login)
ORDER BY
    CASE m.map_type WHEN N''MAPPED'' THEN 0 ELSE 1 END,
    ISNULL(m.login_name, m.db_user_name),
    m.database_name,
    m.db_user_name;';

    EXEC sys.sp_executesql @sql, N'@login SYSNAME', @login;
END;

PRINT N'';
PRINT N'===== Logins with no database user =====';

SET @sql = N'
SELECT
    LEFT(sp.name, 30) AS login,
    LEFT(sp.type_desc, 20) AS type,
    CASE sp.is_disabled WHEN 1 THEN ''DISABLED'' ELSE ''ENABLED'' END AS status,
    LEFT(CONVERT(VARCHAR(19), sp.create_date, 120), 20) AS created
FROM sys.server_principals sp
WHERE sp.type IN (N''S'', N''U'', N''G'')
  AND sp.name NOT LIKE N''##%''
  AND (@login = N'''' OR sp.name = @login)';

IF @mapped <> N''
BEGIN
    SET @sql = @sql + N'
  AND NOT EXISTS (
        SELECT 1
        FROM (' + @mapped + N') mapped
        WHERE mapped.login_name = sp.name)';
END;

SET @sql = @sql + N'
ORDER BY sp.name;';

EXEC sys.sp_executesql @sql, N'@login SYSNAME', @login;
