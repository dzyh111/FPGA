param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$project = [System.IO.Path]::GetFullPath($ProjectRoot)
$name = 'HX4S20_Multimedia_1024x600'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pending = @()
foreach ($extension in @('al','prj')) {
    $path = Join-Path $project ($name + '.' + $extension)
    $original = [System.IO.File]::ReadAllText($path)
    $run = [regex]::Match($original,'(?s)(<Run Name="syn_1"[^>]*>)(.*?)(</Run>)')
    if (-not $run.Success) { throw "Synthesis run syn_1 missing: $path" }
    $content = $run.Groups[2].Value
    $strategy = [regex]::Match($content,'(?s)(<Strategy\b[^>]*>)(.*?)(</Strategy>)')
    if (-not $strategy.Success) { throw "Synthesis strategy missing: $path" }
    $strategyBody = $strategy.Groups[2].Value
    $gate = [regex]::Match($strategyBody,'(?s)(<GateProperty>)(.*?)(</GateProperty>)')
    if ($gate.Success) {
        $gateBody = $gate.Groups[2].Value
        if ([regex]::IsMatch($gateBody,'(?s)<map_mode>.*?</map_mode>')) {
            $gateBody = [regex]::Replace($gateBody,'(?s)<map_mode>.*?</map_mode>','<map_mode>area_prior</map_mode>')
        } else {
            $gateBody += "`n                    <map_mode>area_prior</map_mode>`n                "
        }
        $replacement = $gate.Groups[1].Value + $gateBody + $gate.Groups[3].Value
        $strategyBody = $strategyBody.Substring(0,$gate.Index) + $replacement + $strategyBody.Substring($gate.Index+$gate.Length)
    } else {
        $strategyBody += "`n                <GateProperty>`n                    <map_mode>area_prior</map_mode>`n                </GateProperty>`n            "
    }
    $replacement = $strategy.Groups[1].Value + $strategyBody + $strategy.Groups[3].Value
    $content = $content.Substring(0,$strategy.Index) + $replacement + $content.Substring($strategy.Index+$strategy.Length)
    $user = [regex]::Match($content,'(?s)(<UserParams>)(.*?)(</UserParams>)')
    $userBody = ''
    if ($user.Success) {
        $userBody = [regex]::Replace($user.Groups[2].Value,'(?s)\s*<param>\s*set_param\s+gate\s+(?:add_map_lut_struct|multi_thread_mapping|map_mode)\s+[^<]*</param>','')
    }
    $newUser = "<UserParams>" + $userBody + "`n                <param>set_param gate add_map_lut_struct high</param>`n                <param>set_param gate multi_thread_mapping partition</param>`n            </UserParams>"
    if ($user.Success) {
        $content = $content.Substring(0,$user.Index) + $newUser + $content.Substring($user.Index+$user.Length)
    } else {
        $content += "`n            " + $newUser + "`n        "
    }
    $newRun = $run.Groups[1].Value + $content + $run.Groups[3].Value
    $changed = $original.Substring(0,$run.Index) + $newRun + $original.Substring($run.Index+$run.Length)
    foreach ($pattern in @('(?s)<Source_Files>.*?</Source_Files>','<Project\b[^>]*>','(?s)<FileSets>.*?</FileSets>')) {
        if ([regex]::Match($original,$pattern).Value -cne [regex]::Match($changed,$pattern).Value) { throw "Protected project metadata changed: $path" }
    }
    $pending += [pscustomobject]@{ Path=$path; Name=($name+'.'+$extension); Original=$original; Changed=$changed; Before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
foreach ($item in $pending) {
    if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Before) { throw "Project changed during preparation: $($item.Path)" }
}
$backupName = 'backup_gui_config_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$backup = Join-Path $project $backupName
if (Test-Path -LiteralPath $backup) { throw "Backup already exists: $backup" }
[System.IO.Directory]::CreateDirectory($backup) | Out-Null
$manifest = @()
foreach ($item in $pending) {
    $saved = Join-Path $backup $item.Name
    Copy-Item -LiteralPath $item.Path -Destination $saved
    if ((Get-FileHash -LiteralPath $saved -Algorithm SHA256).Hash -ne $item.Before) { throw "Backup verification failed: $saved" }
}
foreach ($item in $pending) {
    [System.IO.File]::WriteAllText($item.Path,$item.Changed,$utf8)
    if ([System.IO.File]::ReadAllText($item.Path) -cne $item.Changed) { throw "Readback differs: $($item.Path)" }
    $manifest += [pscustomobject]@{ File=$item.Name; Before=$item.Before; After=(Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash }
}
$record = [pscustomobject]@{ Purpose='GUI synthesis Run metadata only'; Parameters='high / area_prior / partition'; Files=$manifest; NoTDInvoked=$true; NoSynthesisRun=$true; SourceEntriesAndProjectPathUnchanged=$true }
[System.IO.File]::WriteAllText((Join-Path $backup 'manifest.json'),($record | ConvertTo-Json -Depth 5),$utf8)
Write-Output "GUI project configuration updated. Backup: $backup"
Write-Output 'No TD, synthesis, placement, routing, or bit generation was invoked.'
Write-Output 'Reopen the AL project in TD after this script. Reset the old runs before a new synthesis.'
