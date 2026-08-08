param(
    [Parameter(Position=0)]
    [ValidateSet('all','claude-code','codex-cli','antigravity-cli','opencode','grok-cli','aider')]
    [string]$Engine = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $repoRoot 'registry\agent-fleet.json'
if (-not (Test-Path $registryPath -PathType Leaf)) {
    throw "Agent fleet registry not found: $registryPath"
}

$fleet = Get-Content $registryPath -Raw | ConvertFrom-Json
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportRoot = Join-Path (Join-Path $HOME '.mk-spacecraft\reports\agent-capabilities') $timestamp
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

$pattern = '(?i)(non[- ]?interactive|exec|run|print|prompt|message|permission|approval|sandbox|network|working[- ]?directory|cwd|directory|json|model|output)'

if ($Engine -eq 'all') {
    $engineIds = @($fleet.engines.PSObject.Properties.Name)
}
else {
    $engineIds = @($Engine)
}

Write-Host "`n=== MK AGENT CAPABILITY PROBE ===" -ForegroundColor Cyan
Write-Host 'Mode        : HELP ONLY'
Write-Host 'Agent launch: DISABLED' -ForegroundColor Yellow
Write-Host "Reports     : $reportRoot"

foreach ($id in $engineIds) {
    $property = $fleet.engines.PSObject.Properties[$id]
    if (-not $property) {
        throw "Unknown fleet engine: $id"
    }

    $engineConfig = $property.Value
    $command = Get-Command $engineConfig.command -ErrorAction SilentlyContinue

    Write-Host "`n--- $id ---" -ForegroundColor Yellow
    if (-not $command) {
        Write-Host '[MISSING] command not found.' -ForegroundColor Red
        continue
    }

    Write-Host "Command: $($engineConfig.command)"
    Write-Host "Path   : $($command.Source)"

    $helpOutput = @(& $engineConfig.command --help 2>&1)
    $helpOk = $?
    $reportPath = Join-Path $reportRoot "$id-help.txt"
    $helpOutput | Set-Content -Path $reportPath -Encoding utf8

    if (-not $helpOk) {
        Write-Host '[WARN] --help returned a non-success exit state. Output was still captured.' -ForegroundColor Yellow
    }

    $matches = @($helpOutput | Select-String -Pattern $pattern | ForEach-Object { $_.Line.Trim() } | Where-Object { $_ } | Select-Object -Unique -First 30)
    if ($matches.Count -eq 0) {
        Write-Host 'No capability keywords matched; showing first help lines:' -ForegroundColor DarkYellow
        $helpOutput | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
    }
    else {
        $matches | ForEach-Object { Write-Host "  $_" }
    }

    Write-Host "Report : $reportPath"
}

Write-Host "`n[MK] Capability probe complete. No agent was launched." -ForegroundColor Green
