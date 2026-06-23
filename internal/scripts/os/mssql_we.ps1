# File Name: mssql_we.ps1
# Purpose: MSSQL session wait and SQL overview with formatted table output (Windows only)
# Created: 20260612  by  huangtingzhong

param(
    [string]$Server = 'localhost'
)

$ErrorActionPreference = 'Stop'

function Get-MssqlInstanceTcpPort {
    $port = $null
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like 'MSSQL*.MSSQLSERVER' } |
        Select-Object -First 1 |
        ForEach-Object {
            $ip = Join-Path $_.PSPath 'MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
            if (Test-Path -LiteralPath $ip) {
                $port = (Get-ItemProperty -LiteralPath $ip -Name TcpPort -ErrorAction SilentlyContinue).TcpPort
            }
        }
    if ($port -and $port -ne '1433') { return $port }
    return $null
}

function New-MssqlConnectionString {
    param([string]$ServerName)
    $port = Get-MssqlInstanceTcpPort
    if ($port) {
        return "Server=$ServerName,$port;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=5;"
    }
    return "Server=$ServerName;Integrated Security=True;TrustServerCertificate=True;Connection Timeout=5;"
}

function Invoke-MssqlDataTable {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Query
    )
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $Query
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $table = New-Object System.Data.DataTable
    [void]$adapter.Fill($table)
    return $table
}

function Write-FormattedSection {
    param(
        [string]$Title,
        [System.Data.DataTable]$Table
    )
    Write-Output ''
    Write-Output ('=' * 100)
    Write-Output $Title
    Write-Output ('=' * 100)
    if ($Table.Rows.Count -eq 0) {
        Write-Output '(no rows)'
        return
    }
    $Table | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_.TrimEnd() } | Write-Output
}

$querySessions = @'
SET NOCOUNT ON;
SELECT TOP 50
    CAST(r.session_id AS VARCHAR(12)) AS SID,
    LEFT(ISNULL(r.wait_type, ''), 30) AS EVENT,
    LEFT(ISNULL(s.login_name, ''), 20) AS USERNAME,
    LEFT(ISNULL(
        SUBSTRING(
            t.text,
            (r.statement_start_offset / 2) + 1,
            CASE
                WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), t.text))
                ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1
            END
        ), ''), 40) AS SQL_TEXT,
    CASE
        WHEN r.total_elapsed_time < 1000 THEN CAST(r.total_elapsed_time AS VARCHAR(12)) + 'MS'
        WHEN r.total_elapsed_time < 1000000 THEN CAST(r.total_elapsed_time / 1000 AS VARCHAR(12)) + 'S'
        ELSE CAST(r.total_elapsed_time / 1000000 AS VARCHAR(12)) + 'KS'
    END AS EXEC_TIME,
    LEFT(ISNULL(s.host_name, ''), 30) AS CLIENT
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
  AND s.is_user_process = 1
ORDER BY r.total_elapsed_time DESC;
'@

$queryTopWait = @'
SET NOCOUNT ON;
SELECT TOP 20
    LEFT(ISNULL(
        SUBSTRING(
            t.text,
            (r.statement_start_offset / 2) + 1,
            CASE
                WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), t.text))
                ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1
            END
        ), ''), 40) AS SQL_SNIPPET,
    LEFT(ISNULL(r.wait_type, ''), 30) AS WAIT_EVENT,
    COUNT(*) AS HCOUNT
FROM sys.dm_exec_requests r
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
  AND t.text IS NOT NULL
GROUP BY
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        CASE
            WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(NVARCHAR(MAX), t.text))
            ELSE (r.statement_end_offset - r.statement_start_offset) / 2 + 1
        END
    ),
    r.wait_type
HAVING COUNT(*) > 1
ORDER BY HCOUNT DESC;
'@

$connStr = New-MssqlConnectionString -ServerName $Server
$conn = New-Object System.Data.SqlClient.SqlConnection $connStr
try {
    $conn.Open()
    $sessions = Invoke-MssqlDataTable -Connection $conn -Query $querySessions
    Write-FormattedSection -Title 'Active sessions (top 50 by elapsed time)' -Table $sessions
    $topWait = Invoke-MssqlDataTable -Connection $conn -Query $queryTopWait
    Write-FormattedSection -Title 'Top wait SQL grouped (HCOUNT > 1)' -Table $topWait
}
finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}
