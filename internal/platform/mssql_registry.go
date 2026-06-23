package platform

import (
	"fmt"
	"strings"
)

const (
	mssqlProbeSQLCmdPrefix = "YTOP_SQLCMD="
	mssqlProbePortPrefix   = "YTOP_MSSQL_PORT="
)

// BuildWindowsMssqlRegistryProbeCmd returns a PowerShell command that locates sqlcmd.exe
// and the default instance TCP port via SQL Server registry keys.
func BuildWindowsMssqlRegistryProbeCmd() string {
	return wrapPowerShellEncoded(windowsMssqlRegistryProbeScript())
}

func windowsMssqlRegistryProbeScript() string {
	return `$ErrorActionPreference='SilentlyContinue'
$ProgressPreference='SilentlyContinue'
$sqlcmd=$null
function Resolve-SqlcmdFromRegPath([string]$binPath) {
  if(-not $binPath){ return $null }
  $c=Join-Path $binPath 'sqlcmd.exe'
  if(Test-Path -LiteralPath $c){ return $c }
  return $null
}
function Resolve-SqlcmdFromVersion([string]$ver) {
  if(-not $ver){ return $null }
  $sdk=Join-Path $env:ProgramFiles ("Microsoft SQL Server\Client SDK\ODBC\{0}\Tools\Binn\sqlcmd.exe" -f $ver)
  if(Test-Path -LiteralPath $sdk){ return $sdk }
  return $null
}
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Client SDK\ODBC' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
  if($sqlcmd){ return }
  foreach($sub in @('Tools\ClientSetup','Tools\Setup')) {
    $p=(Get-ItemProperty (Join-Path $_.PSPath $sub) -Name Path -ErrorAction SilentlyContinue).Path
    $c=Resolve-SqlcmdFromRegPath $p
    if($c){ $script:sqlcmd=$c; break }
  }
}
if(-not $sqlcmd){
  $verKeys=@(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d+$' } | Sort-Object { [int]$_.PSChildName } -Descending)
  foreach($key in $verKeys){
    if($sqlcmd){ break }
    $ver=$key.PSChildName
    $p=(Get-ItemProperty (Join-Path $key.PSPath 'Tools\ClientSetup') -Name Path -ErrorAction SilentlyContinue).Path
    $c=Resolve-SqlcmdFromRegPath $p
    if(-not $c){ $c=Resolve-SqlcmdFromVersion $ver }
    if($c){ $script:sqlcmd=$c; break }
  }
}
if(-not $sqlcmd){
  $root=Join-Path $env:ProgramFiles 'Microsoft SQL Server'
  if(Test-Path -LiteralPath $root){
    $found=Get-ChildItem -LiteralPath $root -Recurse -Filter sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if($found){ $script:sqlcmd=$found.FullName }
  }
}
$port=''
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'MSSQL*.MSSQLSERVER' } | Select-Object -First 1 | ForEach-Object {
  $ip=Join-Path $_.PSPath 'MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
  if(Test-Path -LiteralPath $ip){ $port=(Get-ItemProperty -LiteralPath $ip -Name TcpPort -ErrorAction SilentlyContinue).TcpPort }
}
Write-Output ('YTOP_SQLCMD='+$sqlcmd)
Write-Output ('YTOP_MSSQL_PORT='+$port)
`
}

// ParseWindowsMssqlRegistryProbeOutput parses probe stdout lines.
func ParseWindowsMssqlRegistryProbeOutput(output string) (sqlcmdPath, tcpPort string, err error) {
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(strings.TrimRight(line, "\r"))
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, mssqlProbeSQLCmdPrefix) {
			sqlcmdPath = strings.TrimSpace(strings.TrimPrefix(line, mssqlProbeSQLCmdPrefix))
			continue
		}
		if strings.HasPrefix(line, mssqlProbePortPrefix) {
			tcpPort = strings.TrimSpace(strings.TrimPrefix(line, mssqlProbePortPrefix))
		}
	}
	if sqlcmdPath == "" {
		return "", tcpPort, fmt.Errorf("sqlcmd path not found in registry probe output")
	}
	return sqlcmdPath, tcpPort, nil
}
