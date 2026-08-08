Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path (Join-Path $repoRoot 'scripts') 'MK.Spacecraft.psm1'

if (-not (Test-Path $modulePath -PathType Leaf)) {
    throw "MK Spacecraft module not found: $modulePath"
}

$markerStart = '# >>> MK Nuclear Spacecraft >>>'
$markerEnd = '# <<< MK Nuclear Spacecraft <<<'
$escapedModulePath = $modulePath.Replace("'", "''")
$block = @"
$markerStart
Import-Module '$escapedModulePath' -Force -DisableNameChecking
$markerEnd
"@

function Set-MKProfileBlock {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][bool]$InstallBlock
    )

    $profileDir = Split-Path -Parent $Path
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $current = Get-Content $Path -Raw
    if ($null -eq $current) { $current = '' }

    $managedPattern = [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
    $current = [regex]::Replace(
        $current,
        $managedPattern,
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $remainingLines = @($current -split "`r?`n" | Where-Object {
        $_ -notmatch '(?i)^\s*Import-Module\s+.*MK\.Spacecraft\.psm1.*$'
    })

    $clean = ($remainingLines -join "`n").TrimEnd()
    if ($InstallBlock) {
        if ($clean) {
            $newProfile = "$clean`n`n$block`n"
        }
        else {
            $newProfile = "$block`n"
        }
    }
    else {
        $newProfile = if ($clean) { "$clean`n" } else { '' }
    }

    Set-Content $Path $newProfile -Encoding utf8
}

# Install into CurrentUserAllHosts so ConsoleHost, VS Code PowerShell,
# and other PowerShell hosts all receive the same Spacecraft commands.
$allHostsProfile = $PROFILE.CurrentUserAllHosts
Set-MKProfileBlock -Path $allHostsProfile -InstallBlock $true

# Remove any older host-specific managed copy to avoid duplicate imports.
$currentHostProfile = $PROFILE.CurrentUserCurrentHost
if ($currentHostProfile -and $currentHostProfile -ne $allHostsProfile -and (Test-Path $currentHostProfile)) {
    Set-MKProfileBlock -Path $currentHostProfile -InstallBlock $false
}

Import-Module $modulePath -Force -DisableNameChecking

Write-Host "`nMK Nuclear Spacecraft commands installed for all current-user PowerShell hosts." -ForegroundColor Green
Write-Host 'Available commands:' -ForegroundColor Cyan
Write-Host '  mk-status'
Write-Host '  mk-start-task <feature|fix|chore|docs|agent|bootstrap> <name>'
Write-Host '  mk-security <quick|full|nuclear>'
Write-Host '  mk-agent-status'
Write-Host '  mk-route <simple|normal|power|nuclear>'
Write-Host '  mk-worktree <status|create|remove> ...'
Write-Host '  mk-checkpoint "message"'
Write-Host "`nAll-hosts profile: $allHostsProfile"
Write-Host "Current host    : $($Host.Name)"
