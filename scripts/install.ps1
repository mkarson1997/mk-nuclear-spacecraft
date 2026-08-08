Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $repoRoot 'scripts\MK.Spacecraft.psm1'

if (-not (Test-Path $modulePath)) {
    throw "MK Spacecraft module not found: $modulePath"
}

$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path -Parent $profilePath
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$escapedModulePath = $modulePath.Replace("'", "''")
$markerStart = '# >>> MK Nuclear Spacecraft >>>'
$markerEnd = '# <<< MK Nuclear Spacecraft <<<'
$block = @"
$markerStart
Import-Module '$escapedModulePath' -Force -DisableNameChecking
$markerEnd
"@

$current = Get-Content $profilePath -Raw

# Remove every previous managed block first, including duplicates.
$managedPattern = [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
$current = [regex]::Replace(
    $current,
    $managedPattern,
    '',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

# Remove legacy one-line imports that predate the managed block.
$remainingLines = @($current -split "`r?`n" | Where-Object {
    $_ -notmatch '(?i)^\s*Import-Module\s+.*MK\.Spacecraft\.psm1.*$'
})

$clean = ($remainingLines -join "`n").TrimEnd()
if ($clean) {
    $newProfile = "$clean`n`n$block`n"
}
else {
    $newProfile = "$block`n"
}

Set-Content $profilePath $newProfile -Encoding utf8

Import-Module $modulePath -Force -DisableNameChecking

Write-Host "`nMK Nuclear Spacecraft commands installed for this PowerShell profile." -ForegroundColor Green
Write-Host 'Available commands:' -ForegroundColor Cyan
Write-Host '  mk-status'
Write-Host '  mk-start-task <feature|fix|chore|docs|agent|bootstrap> <name>'
Write-Host '  mk-security <quick|full|nuclear>'
Write-Host '  mk-agent-status'
Write-Host '  mk-route <simple|normal|power|nuclear>'
Write-Host '  mk-worktree <status|create|remove> ...'
Write-Host '  mk-checkpoint "message"'
Write-Host "`nProfile: $profilePath"
