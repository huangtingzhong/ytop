# File Name: win_counter.ps1
# Purpose: Windows CPU and memory counter snapshot (Windows only)
# Created: 20260612  by  huangtingzhong

$ErrorActionPreference = 'Stop'

$counters = @(
    '\Processor(_Total)\% Processor Time',
    '\Memory\Available MBytes',
    '\Memory\Committed Bytes'
)

$samples = Get-Counter -Counter $counters -SampleInterval 1 -MaxSamples 1

foreach ($sample in $samples.CounterSamples) {
    $name = $sample.Path
    if ($name -match '\\([^\\]+)$') {
        $name = $Matches[1]
    }
    $value = [math]::Round($sample.CookedValue, 2)
    Write-Output ("{0,-40} {1}" -f $name, $value)
}
