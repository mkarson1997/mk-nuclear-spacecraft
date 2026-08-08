param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('status','review')]
    [string]$Action,

    [Parameter(Position=1)]
    [ValidateSet('grok-cli','codex-cli')]
    [string]$Engine = 'grok-cli',

    [Parameter(Position=2)]
    [string]$Prompt,

    [switch]$Qualification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $resolved = [System.IO.Path]::GetFullPath((Resolve-Path $Path).Path)
    return $resolved.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
}

$spacecraftRoot = Get-NormalizedPath (Join-Path $PSScriptRoot '..\..')
$registryPath = Join-Path $spacecraftRoot 'registry\agent-fleet.json'
if (-not (Test-Path $registryPath -PathType Leaf)) {
    throw "Agent fleet registry not found: $registryPath"
}
$fleet = Get-Content $registryPath -Raw | ConvertFrom-Json

$repoRootRaw = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $? -or -not $repoRootRaw) {
    throw 'Not inside a Git repository.'
}
$repoRoot = Get-NormalizedPath $repoRootRaw.Trim()

if ($Action -eq 'status') {
    Write-Host "`n=== MK AGENT LAUNCHER ===" -ForegroundColor Cyan
    Write-Host 'Qualification-only launcher : enabled'
    Write-Host "Project execution enabled   : $($fleet.policy.project_execution_enabled)"
    Write-Host 'Qualified review engines    : grok-cli, codex-cli'
    Write-Host 'Writer launch               : disabled' -ForegroundColor Yellow
    Write-Host 'Production access           : disabled' -ForegroundColor Yellow
    Write-Host 'Semantic completion check   : enabled'
    Write-Host 'Codex review sandbox        : read-only + JSONL completion gate'
    Write-Host "Spacecraft root             : $spacecraftRoot"
    exit 0
}

if (-not $Qualification) {
    throw 'Agent launch is blocked unless -Qualification is explicitly supplied.'
}
if ($fleet.policy.project_execution_enabled -ne $false) {
    throw 'Unexpected fleet state: project execution must remain disabled during qualification.'
}
if ($repoRoot -ne $spacecraftRoot) {
    throw "Qualification launcher may run only inside MK Nuclear Spacecraft. Current repository: $repoRoot"
}

$branch = (git branch --show-current).Trim()
if (-not $branch) {
    throw 'Detached HEAD is not supported for agent qualification.'
}
if ($branch -in @('main','master')) {
    throw 'Agent qualification is blocked on main/master. Use a task branch.'
}

$beforeStatus = @(git status --porcelain=v1)
if (-not $?) { throw 'Failed to inspect Git status before agent launch.' }
if ($beforeStatus.Count -gt 0) {
    throw 'Agent qualification requires a clean working tree.'
}
$beforeHead = (git rev-parse HEAD).Trim()
if (-not $?) { throw 'Failed to read HEAD before agent launch.' }

if (-not $Prompt) {
    $Prompt = 'Review the current MK Nuclear Spacecraft Agent Fleet control-plane change for safety, correctness, and isolation risks. Do not modify files. Return concise findings only.'
}
if ($Prompt.Length -gt 6000) {
    throw 'Qualification prompt is too large. Keep it under 6000 characters.'
}
$secretPattern = '(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}'
if ($Prompt -match $secretPattern) {
    throw 'Qualification prompt appears to contain a credential or private key.'
}

$engineProperty = $fleet.engines.PSObject.Properties[$Engine]
if (-not $engineProperty) {
    throw "Unknown fleet engine: $Engine"
}
$commandName = $engineProperty.Value.command
$command = Get-Command $commandName -ErrorAction SilentlyContinue
if (-not $command) {
    throw "Fleet engine command not found: $commandName"
}

$guard = @'
MK QUALIFICATION SAFETY CONTRACT:
- This is a read-only review of MK Nuclear Spacecraft itself.
- Do not edit, create, delete, rename, move, stage, commit, or push files.
- Do not change Git configuration, branches, worktrees, hooks, credentials, permissions, or environment configuration.
- Do not deploy, contact production systems, or access secrets.
- Do not invoke external integrations or browse unrelated external resources.
- Inspect only what is necessary to answer the review request.
- If an action would require mutation, report it as a recommendation instead of performing it.
'@
$guardedPrompt = "$guard`nREVIEW REQUEST:`n$Prompt"

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportRoot = Join-Path (Join-Path $HOME '.mk-spacecraft\reports\agent-launches') $timestamp
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$outputPath = Join-Path $reportRoot "$Engine-review-output.txt"
$metadataPath = Join-Path $reportRoot 'launch.json'
$eventsPath = Join-Path $reportRoot "$Engine-events.jsonl"
$stderrPath = Join-Path $reportRoot "$Engine-stderr.txt"
$lastMessagePath = Join-Path $reportRoot "$Engine-last-message.txt"

Write-Host "`n=== MK AGENT QUALIFICATION REVIEW ===" -ForegroundColor Cyan
Write-Host "Engine      : $Engine"
Write-Host "Branch      : $branch"
Write-Host "HEAD        : $beforeHead"
Write-Host 'Access      : READ-ONLY REVIEW'
Write-Host 'Project run : BLOCKED'
if ($Engine -eq 'codex-cli') {
    Write-Host 'Sandbox     : read-only'
    Write-Host 'Result gate : JSONL events + final message'
}
Write-Host "Report      : $outputPath"

$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$rawOutput = @()
$runOk = $false
$codexJsonOutput = @()

Push-Location $repoRoot
try {
    switch ($Engine) {
        'grok-cli' {
            $rawOutput = @(& $commandName --cwd $repoRoot --permission-mode plan --output-format json --single $guardedPrompt 2>&1)
            $runOk = $?
        }
        'codex-cli' {
            $codexJsonOutput = @(& $commandName exec -s read-only --json -o $lastMessagePath $guardedPrompt 2>$stderrPath)
            $runOk = $?
            $codexJsonOutput | Set-Content -Path $eventsPath -Encoding utf8

            $finalMessage = ''
            if (Test-Path $lastMessagePath -PathType Leaf) {
                $finalMessage = (Get-Content $lastMessagePath -Raw).Trim()
            }
            $rawOutput = @($finalMessage)
            $rawOutput | Set-Content -Path $outputPath -Encoding utf8
        }
    }
}
finally {
    Pop-Location
}

if ($Engine -ne 'codex-cli') {
    $rawOutput | Set-Content -Path $outputPath -Encoding utf8
}

$semanticOk = $runOk
$engineStopReason = $null
if ($Engine -eq 'grok-cli' -and $rawOutput.Count -gt 0) {
    try {
        $parsedOutput = (($rawOutput -join "`n") | ConvertFrom-Json)
        if ($parsedOutput.PSObject.Properties.Name -contains 'stopReason') {
            $engineStopReason = [string]$parsedOutput.stopReason
            if ($engineStopReason -match '(?i)cancel|error|fail|abort') {
                $semanticOk = $false
            }
        }
        if ($parsedOutput.PSObject.Properties.Name -contains 'text' -and [string]::IsNullOrWhiteSpace([string]$parsedOutput.text)) {
            $semanticOk = $false
        }
    }
    catch {
        $semanticOk = $false
        $engineStopReason = 'UNPARSEABLE_JSON'
    }
}
elseif ($Engine -eq 'codex-cli') {
    $eventParseFailed = $false
    $errorEventDetected = $false
    $completionEventDetected = $false

    foreach ($line in $codexJsonOutput) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        try {
            $event = $text | ConvertFrom-Json
        }
        catch {
            $eventParseFailed = $true
            continue
        }

        $eventType = ''
        if ($event.PSObject.Properties.Name -contains 'type') {
            $eventType = [string]$event.type
        }

        if ($eventType -match '(?i)(^|\.)(error|failed|failure|aborted|cancelled)$') {
            $errorEventDetected = $true
        }
        if ($eventType -match '(?i)(turn\.completed|completed)$') {
            $completionEventDetected = $true
        }
        if ($event.PSObject.Properties.Name -contains 'error' -and $null -ne $event.error) {
            $errorEventDetected = $true
        }
    }

    $finalMessageText = ''
    if (Test-Path $lastMessagePath -PathType Leaf) {
        $finalMessageText = (Get-Content $lastMessagePath -Raw).Trim()
    }

    if (-not $runOk) {
        $semanticOk = $false
        $engineStopReason = 'PROCESS_FAILURE'
    }
    elseif ($eventParseFailed) {
        $semanticOk = $false
        $engineStopReason = 'UNPARSEABLE_JSONL'
    }
    elseif ($errorEventDetected) {
        $semanticOk = $false
        $engineStopReason = 'ERROR_EVENT'
    }
    elseif ([string]::IsNullOrWhiteSpace($finalMessageText)) {
        $semanticOk = $false
        $engineStopReason = 'EMPTY_FINAL_MESSAGE'
    }
    elseif (-not $completionEventDetected) {
        $semanticOk = $false
        $engineStopReason = 'NO_COMPLETION_EVENT'
    }
    else {
        $semanticOk = $true
        $engineStopReason = 'COMPLETED'
    }
}

$afterHead = (git rev-parse HEAD).Trim()
if (-not $?) { throw 'Failed to read HEAD after agent launch.' }
$afterStatus = @(git status --porcelain=v1)
if (-not $?) { throw 'Failed to inspect Git status after agent launch.' }
$mutationDetected = ($afterHead -ne $beforeHead -or $afterStatus.Count -gt 0)

$metadata = [ordered]@{
    schema = 1
    action = 'review'
    qualification = $true
    engine = $Engine
    command = $commandName
    branch = $branch
    head_before = $beforeHead
    head_after = $afterHead
    started_at_utc = $startedAt
    finished_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    command_success = $runOk
    semantic_success = $semanticOk
    engine_stop_reason = $engineStopReason
    mutation_detected = $mutationDetected
    output_file = $outputPath
    events_file = if ($Engine -eq 'codex-cli') { $eventsPath } else { $null }
    stderr_file = if ($Engine -eq 'codex-cli') { $stderrPath } else { $null }
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $metadataPath -Encoding utf8

if ($mutationDetected) {
    Write-Host '[BLOCK] Repository mutation detected after a read-only qualification launch.' -ForegroundColor Red
    Write-Host 'No automatic reset was performed. Inspect the working tree before continuing.' -ForegroundColor Yellow
    throw 'Read-only agent qualification violated repository immutability.'
}
if (-not $runOk) {
    Write-Host "[FAIL] Agent command returned a failure state. See: $outputPath" -ForegroundColor Red
    if ($Engine -eq 'codex-cli') { Write-Host "stderr      : $stderrPath" -ForegroundColor Yellow }
    throw 'Agent qualification review failed.'
}
if (-not $semanticOk) {
    Write-Host "[FAIL] Agent process exited cleanly but did not complete semantically. Stop reason: $engineStopReason" -ForegroundColor Red
    Write-Host "See: $outputPath" -ForegroundColor Yellow
    if ($Engine -eq 'codex-cli') {
        Write-Host "Events      : $eventsPath" -ForegroundColor Yellow
        Write-Host "stderr      : $stderrPath" -ForegroundColor Yellow
    }
    throw 'Agent qualification review was incomplete or cancelled.'
}

Write-Host '[PASS] Agent completed semantically and the repository remained Git-state clean.' -ForegroundColor Green
Write-Host "Metadata    : $metadataPath"
Write-Host "`n--- Agent output preview ---" -ForegroundColor Yellow
$rawOutput | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
Write-Host "`n[MK] Qualification review complete. No project execution was enabled." -ForegroundColor Green
