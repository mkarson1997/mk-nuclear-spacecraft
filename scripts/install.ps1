Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $repoRoot 'scripts\MK.Spacecraft.psm1'

if (-not (Test-Path $modulePath)) {
    throw "MK Spacecraft module not found: $modulePath"
}

$profileDir = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $PROFILE.CurrentUserCurrentHost)) {
    New-Item -ItemType File -Path $PROFILE.CurrentUserCurrentHost -Force | Out-Null
}

$escapedModulePath = $modulePath.Replace("'", "''")
$markerStart = '# >>> MK Nuclear Spacecraft >>>'
$markerEnd = '# <<< MK Nuclear Spacecraft <<<'
$block = @"
$markerStart
Import-Module '$escapedModulePath' -Force
$markerEnd
"@

$current = Get-Content $PROFILE.CurrentUserCurrentHost -Raw
$pattern = [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
if ($current -match $pattern) {
    $current = [regex]::Replace($current, $pattern, $block, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Set-Content $PROFILE.CurrentUserCurrentHost $current -Encoding utf8
} else {
    Add-Content $PROFILE.CurrentUserCurrentHost "`n$block" -Encoding utf8
}

Import-Module $modulePath -Force

Write-Host "`nMK Nuclear Spacecraft commands installed for this PowerShell profile." -ForegroundColor Green
Write-Host 'Available commands:' -ForegroundColor Cyan
Write-Host '  mk-status'
Write-Host '  mk-start-task <feature|fix|chore|docs|agent|bootstrap> <name>'
Write-Host '  mk-checkpoint "message"'
Write-Host "`nProfile: $($PROFILE.CurrentUserCurrentHost)"
