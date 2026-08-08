param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('status','route')]
    [string]$Action,

    [Parameter(Position=1)]
    [ValidateSet('simple','normal','power','nuclear')]
    [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$registryPath = Join-Path $repoRoot 'registry\agent-fleet.json'

if (-not (Test-Path $registryPath -PathType Leaf)) {
    throw "Agent fleet registry not found: $registryPath"
}

$fleet = Get-Content $registryPath -Raw | ConvertFrom-Json

function Get-MKEngineStatus {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)]$Engine
    )

    $command = Get-Command $Engine.command -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            Id = $Id
            Status = 'MISSING'
            Version = ''
            Path = ''
        }
    }

    $args = @($Engine.version_args)
    $output = (& $Engine.command @args 2>&1 | Select-Object -First 2) -join ' | '
    $nativeOk = $?

    [pscustomobject]@{
        Id = $Id
        Status = if ($nativeOk) { 'READY' } else { 'ERROR' }
        Version = $output.Trim()
        Path = $command.Source
    }
}

switch ($Action) {
    'status' {
        Write-Host "`n=== MK AGENT FLEET STATUS ===" -ForegroundColor Cyan
        Write-Host "Fleet version      : $($fleet.fleet_version)"
        Write-Host "Project execution  : $($fleet.policy.project_execution_enabled)"
        Write-Host "Writer worktrees   : $($fleet.policy.concurrent_writers_require_worktrees)"
        Write-Host ''

        $rows = foreach ($property in $fleet.engines.PSObject.Properties) {
            Get-MKEngineStatus -Id $property.Name -Engine $property.Value
        }

        $rows | Format-Table -AutoSize Id, Status, Version, Path

        $missing = @($rows | Where-Object { $_.Status -ne 'READY' })
        if ($missing.Count -gt 0) {
            Write-Host "[WARN] $($missing.Count) fleet engine(s) are not ready." -ForegroundColor Yellow
            exit 2
        }

        Write-Host '[MK] All registered fleet engines are ready.' -ForegroundColor Green
        exit 0
    }

    'route' {
        if (-not $Mode) {
            throw 'Mode is required for route. Use simple, normal, power, or nuclear.'
        }

        $routeProperty = $fleet.routing.PSObject.Properties[$Mode]
        if (-not $routeProperty) {
            throw "Unknown routing mode: $Mode"
        }

        $route = $routeProperty.Value
        $maxAgents = $fleet.policy.max_agents.$Mode

        Write-Host "`n=== MK ROUTE: $($Mode.ToUpperInvariant()) ===" -ForegroundColor Cyan
        Write-Host "Description : $($route.description)"
        Write-Host "Agent ceiling: $maxAgents"
        Write-Host "Execution    : PLAN ONLY (project execution is disabled during qualification)" -ForegroundColor Yellow
        Write-Host ''

        $index = 0
        foreach ($slot in $route.slots) {
            $index++
            $engine = $fleet.engines.PSObject.Properties[$slot.engine].Value
            $command = Get-Command $engine.command -ErrorAction SilentlyContinue
            $availability = if ($command) { 'READY' } else { 'MISSING' }
            $requirement = if ($slot.required) { 'required' } else { 'optional' }

            Write-Host ("{0,2}. {1,-18} role={2,-24} {3,-8} {4}" -f $index, $slot.engine, $slot.role, $requirement, $availability)
        }

        Write-Host "`n[MK] Route generated without launching any agent." -ForegroundColor Green
        exit 0
    }
}
