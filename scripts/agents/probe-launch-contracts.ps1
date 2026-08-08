param(
    [Parameter(Position=0)]
    [ValidateSet('all','claude-code','codex-cli','antigravity-cli','opencode','grok-cli','aider')]
    [string]$Engine = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportRoot = Join-Path (Join-Path $HOME '.mk-spacecraft\reports\agent-launch-contracts') $timestamp
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

$contracts = [ordered]@{
    'claude-code' = @(
        @{ Label = 'root-help'; Command = 'claude'; Args = @('--help') }
    )
    'codex-cli' = @(
        @{ Label = 'exec-help'; Command = 'codex'; Args = @('exec','--help') },
        @{ Label = 'review-help'; Command = 'codex'; Args = @('review','--help') },
        @{ Label = 'sandbox-help'; Command = 'codex'; Args = @('sandbox','--help') }
    )
    'antigravity-cli' = @(
        @{ Label = 'root-help'; Command = 'agy'; Args = @('--help') }
    )
    'opencode' = @(
        @{ Label = 'run-help'; Command = 'opencode'; Args = @('run','--help') }
    )
    'grok-cli' = @(
        @{ Label = 'root-help'; Command = 'grok'; Args = @('--help') }
    )
    'aider' = @(
        @{ Label = 'root-help'; Command = 'aider'; Args = @('--help') }
    )
}

$pattern = '(?i)(sandbox|approval|permission|read[- ]?only|workspace|write|network|cwd|directory|non[- ]?interactive|headless|print|single|prompt|message|json|output|model|dry[- ]?run|commit|git|danger|auto)'

if ($Engine -eq 'all') {
    $engineIds = @($contracts.Keys)
}
else {
    $engineIds = @($Engine)
}

Write-Host "`n=== MK AGENT LAUNCH CONTRACT PROBE ===" -ForegroundColor Cyan
Write-Host 'Mode        : HELP ONLY'
Write-Host 'Agent launch: DISABLED' -ForegroundColor Yellow
Write-Host "Reports     : $reportRoot"

foreach ($engineId in $engineIds) {
    Write-Host "`n--- $engineId ---" -ForegroundColor Yellow

    foreach ($probe in $contracts[$engineId]) {
        $command = Get-Command $probe.Command -ErrorAction SilentlyContinue
        if (-not $command) {
            Write-Host "[MISSING] $($probe.Command)" -ForegroundColor Red
            continue
        }

        Write-Host "`n[$($probe.Label)] $($probe.Command) $($probe.Args -join ' ')" -ForegroundColor DarkCyan
        $output = @(& $probe.Command @($probe.Args) 2>&1)
        $ok = $?
        $reportPath = Join-Path $reportRoot "$engineId-$($probe.Label).txt"
        $output | Set-Content -Path $reportPath -Encoding utf8

        if (-not $ok) {
            Write-Host '[WARN] Help command returned a non-success state; output was captured.' -ForegroundColor Yellow
        }

        $matches = @(
            $output |
                Select-String -Pattern $pattern |
                ForEach-Object { $_.Line.Trim() } |
                Where-Object { $_ } |
                Select-Object -Unique -First 60
        )

        if ($matches.Count -eq 0) {
            $output | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        }
        else {
            $matches | ForEach-Object { Write-Host "  $_" }
        }

        Write-Host "Report : $reportPath"
    }
}

Write-Host "`n[MK] Launch contract probe complete. No agent was launched." -ForegroundColor Green
