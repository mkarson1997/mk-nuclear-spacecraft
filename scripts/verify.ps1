Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (git rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or -not $root) {
    throw 'Not inside a Git repository.'
}

$requiredFiles = @(
    'AGENTS.md',
    'agents/FLEET.md',
    'registry/tools.yaml',
    'registry/skills.yaml',
    'registry/agents.yaml',
    'registry/agent-fleet.json',
    'registry/services.yaml',
    'registry/security-lock.json',
    'policies/security/BASELINE.md',
    'policies/cloud/WORKSPACE.md',
    'scripts/MK.Spacecraft.psm1',
    'scripts/install.ps1',
    'scripts/agents/agent-fleet.ps1',
    'scripts/agents/worktree-manager.ps1',
    'scripts/agents/agent-launcher.ps1',
    'scripts/security/run-security.ps1',
    'scripts/security/check-staged-secrets.ps1',
    'scripts/security/install-security-tools.ps1'
)

Write-Host "`n=== MK VERIFY ===" -ForegroundColor Cyan

foreach ($relative in $requiredFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "Required file missing: $relative"
    }
}
Write-Host '[OK] Required control-plane files exist.' -ForegroundColor Green

$powerShellFiles = @(Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1', '.psm1') -and
    $_.FullName -notmatch '[\\/]\.git[\\/]'
})

foreach ($file in $powerShellFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if ($errors.Count -gt 0) {
        Write-Host "[FAIL] PowerShell parse errors: $($file.FullName)" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $($_.Message)" -ForegroundColor Red }
        exit 1
    }
}
Write-Host "[OK] PowerShell syntax parsed: $($powerShellFiles.Count) files." -ForegroundColor Green

$lockPath = Join-Path $root 'registry/security-lock.json'
$lock = Get-Content $lockPath -Raw | ConvertFrom-Json
if ($lock.schema -ne 1) {
    throw "Unsupported security-lock schema: $($lock.schema)"
}
if ($lock.platform -ne 'windows-amd64') {
    throw "Unexpected locked security platform: $($lock.platform)"
}

foreach ($toolName in @('gitleaks','trivy','semgrep','zizmor')) {
    $tool = $lock.tools.$toolName
    if (-not $tool -or -not $tool.version) {
        throw "Security tool is not version-pinned: $toolName"
    }
}
if (-not $lock.bootstrap.pipx.version) {
    throw 'pipx bootstrap dependency is not version-pinned.'
}
Write-Host '[OK] Security lock schema and pinned versions validated.' -ForegroundColor Green

$fleetPath = Join-Path $root 'registry/agent-fleet.json'
$fleet = Get-Content $fleetPath -Raw | ConvertFrom-Json
if ($fleet.schema -ne 1) {
    throw "Unsupported agent-fleet schema: $($fleet.schema)"
}
if (-not $fleet.fleet_version) {
    throw 'Agent fleet version is missing.'
}
if ($fleet.policy.project_execution_enabled -ne $false) {
    throw 'Project execution must remain disabled during Agent Fleet qualification.'
}

$expectedEngines = @('claude-code','codex-cli','antigravity-cli','opencode','grok-cli','aider')
foreach ($engineName in $expectedEngines) {
    $engine = $fleet.engines.PSObject.Properties[$engineName]
    if (-not $engine -or -not $engine.Value.command) {
        throw "Agent fleet engine is missing or invalid: $engineName"
    }
}

$expectedModes = @('simple','normal','power','nuclear')
foreach ($mode in $expectedModes) {
    $route = $fleet.routing.PSObject.Properties[$mode]
    $ceiling = $fleet.policy.max_agents.$mode
    if (-not $route -or -not $route.Value.slots -or -not $ceiling) {
        throw "Agent route is incomplete: $mode"
    }
    if (@($route.Value.slots).Count -gt [int]$ceiling) {
        throw "Agent route exceeds configured ceiling: $mode"
    }
}
Write-Host '[OK] Agent fleet registry and qualification guard validated.' -ForegroundColor Green

git diff --check
if ($LASTEXITCODE -ne 0) {
    throw 'git diff --check failed.'
}

git diff --cached --check
if ($LASTEXITCODE -ne 0) {
    throw 'git diff --cached --check failed.'
}
Write-Host '[OK] Git whitespace/conflict checks passed.' -ForegroundColor Green

Write-Host "`n[MK] Verification passed." -ForegroundColor Green
