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
    'registry/agent-execution-policy.json',
    'registry/services.yaml',
    'registry/security-lock.json',
    'policies/security/BASELINE.md',
    'policies/cloud/WORKSPACE.md',
    'qualification/agent-canary/writer-output.txt',
    'scripts/MK.Spacecraft.psm1',
    'scripts/install.ps1',
    'scripts/agents/agent-fleet.ps1',
    'scripts/agents/worktree-manager.ps1',
    'scripts/agents/agent-launcher.ps1',
    'scripts/agents/writer-runtime.ps1',
    'scripts/runtime/trusted-runtime.ps1',
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

$securityLockPath = Join-Path $root 'registry/security-lock.json'
$securityLock = Get-Content $securityLockPath -Raw | ConvertFrom-Json
if ($securityLock.schema -ne 1) {
    throw "Unsupported security-lock schema: $($securityLock.schema)"
}
if ($securityLock.platform -ne 'windows-amd64') {
    throw "Unexpected locked security platform: $($securityLock.platform)"
}

foreach ($toolName in @('gitleaks','trivy','semgrep','zizmor')) {
    $tool = $securityLock.tools.$toolName
    if (-not $tool -or -not $tool.version) {
        throw "Security tool is not version-pinned: $toolName"
    }
}
if (-not $securityLock.bootstrap.pipx.version) {
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
    throw 'Project execution must remain disabled during Writer Safety qualification.'
}
if (-not $fleet.roles) {
    throw 'Authoritative role policy is missing from agent-fleet.json.'
}

$compatAgentRegistry = Get-Content (Join-Path $root 'registry/agents.yaml') -Raw
if ($compatAgentRegistry -notmatch '(?m)^authority:\s*registry/agent-fleet\.json\s*$' -or
    $compatAgentRegistry -notmatch '(?m)^deprecated:\s*true\s*$') {
    throw 'registry/agents.yaml must remain a deprecated pointer to registry/agent-fleet.json.'
}

$expectedEngines = @('claude-code','codex-cli','antigravity-cli','opencode','grok-cli','aider')
foreach ($engineName in $expectedEngines) {
    $engineProperty = $fleet.engines.PSObject.Properties[$engineName]
    if (-not $engineProperty -or -not $engineProperty.Value.command) {
        throw "Agent fleet engine is missing or invalid: $engineName"
    }

    foreach ($roleName in @($engineProperty.Value.roles)) {
        $roleProperty = $fleet.roles.PSObject.Properties[[string]$roleName]
        if (-not $roleProperty) {
            throw "Engine '$engineName' references unknown role '$roleName'."
        }

        $role = $roleProperty.Value
        if ($role.production_access -ne $false) {
            throw "Fleet role '$roleName' must not imply production access during Writer Safety qualification."
        }
        if ($role.write_repository -eq $true) {
            if ($role.isolated_worktree -ne $true) {
                throw "Writer role '$roleName' must require an isolated worktree."
            }
            if ($engineProperty.Value.default_write -ne $true) {
                throw "Writer role '$roleName' is assigned to non-writer engine '$engineName'."
            }
        }
    }
}

$expectedModes = @('simple','normal','power','nuclear')
foreach ($mode in $expectedModes) {
    $routeProperty = $fleet.routing.PSObject.Properties[$mode]
    $ceiling = $fleet.policy.max_agents.$mode
    if (-not $routeProperty -or -not $routeProperty.Value.slots -or -not $ceiling) {
        throw "Agent route is incomplete: $mode"
    }
    if (@($routeProperty.Value.slots).Count -gt [int]$ceiling) {
        throw "Agent route exceeds configured ceiling: $mode"
    }

    foreach ($slot in @($routeProperty.Value.slots)) {
        $slotEngineProperty = $fleet.engines.PSObject.Properties[[string]$slot.engine]
        if (-not $slotEngineProperty) {
            throw "Route '$mode' references unknown engine '$($slot.engine)'."
        }
        if (-not (@($slotEngineProperty.Value.roles) -contains [string]$slot.role)) {
            throw "Route '$mode' assigns unauthorized engine-role pair '$($slot.engine)/$($slot.role)'."
        }
        if (-not $fleet.roles.PSObject.Properties[[string]$slot.role]) {
            throw "Route '$mode' references unknown role '$($slot.role)'."
        }
    }
}

$worktreeManagerSource = Get-Content (Join-Path $root 'scripts/agents/worktree-manager.ps1') -Raw
foreach ($requiredControl in @(
    'Assert-MKWriterAssignment',
    'Enter-MKWorktreeLock',
    'Write-MKLeaseAtomic',
    'Read-MKLease',
    'lease_id',
    'coordinator_head'
)) {
    if ($worktreeManagerSource -notmatch [regex]::Escape($requiredControl)) {
        throw "Writer worktree control is missing required lease/lock marker: $requiredControl"
    }
}
Write-Host '[OK] Agent fleet roles, routing, writer leases, and qualification guard validated.' -ForegroundColor Green

$executionPath = Join-Path $root 'registry/agent-execution-policy.json'
$execution = Get-Content $executionPath -Raw | ConvertFrom-Json
if ($execution.schema -ne 1) {
    throw "Unsupported agent-execution-policy schema: $($execution.schema)"
}
if ($execution.project_writer_execution_enabled -ne $false) {
    throw 'Project writer execution must remain disabled before trusted-runtime qualification completes.'
}
if ($execution.writer_qualification_enabled -ne $false) {
    throw 'Writer qualification launch must remain disabled in this layer.'
}
if ($execution.trusted_runtime.install_from_branch -ne 'main') {
    throw 'Trusted writer runtime must be installed only from main.'
}
if ($execution.trusted_runtime.require_clean_source -ne $true -or
    $execution.trusted_runtime.require_head_equal_origin -ne $true -or
    $execution.trusted_runtime.require_remote_main_match -ne $true) {
    throw 'Trusted writer runtime source-integrity gates must remain enabled.'
}
if ($execution.trusted_runtime.required_command_type -ne 'Application' -or
    $execution.trusted_runtime.required_executable_extension -ne '.exe') {
    throw 'Trusted writer runtime must require a direct application executable.'
}
if ($execution.writer.qualification_engine -ne 'codex-cli' -or $execution.writer.qualification_role -ne 'implementer') {
    throw 'First writer qualification is pinned to codex-cli/implementer.'
}
if ($execution.writer.required_branch_prefix -ne 'agent-work/') {
    throw 'Writer branch namespace must remain agent-work/.'
}
if ($execution.writer.allow_commit -ne $false -or $execution.writer.allow_push -ne $false -or $execution.writer.production_access -ne $false) {
    throw 'Writer qualification must deny commit, push, and production access.'
}
if ($execution.writer.sandbox_mode -ne 'workspace-write') {
    throw 'Writer qualification sandbox mode must remain workspace-write.'
}
$allowedPaths = @($execution.writer.allowed_qualification_paths)
if ($allowedPaths.Count -ne 1 -or $allowedPaths[0] -ne 'qualification/agent-canary/writer-output.txt') {
    throw 'Writer qualification must be restricted to the single canary output path.'
}
if (-not (@($execution.protected_refs) -contains 'refs/heads/main') -or
    -not (@($execution.protected_refs) -contains 'refs/remotes/origin/main')) {
    throw 'Protected-ref firewall must include local and remote-tracking main refs.'
}

$trustedRuntimeSource = Get-Content (Join-Path $root 'scripts/runtime/trusted-runtime.ps1') -Raw
foreach ($marker in @('require_remote_main_match','runtime-manifest.json','Get-FileHash','source_commit')) {
    if ($trustedRuntimeSource -notmatch [regex]::Escape($marker)) {
        throw "Trusted runtime installer is missing required integrity marker: $marker"
    }
}
$writerRuntimeSource = Get-Content (Join-Path $root 'scripts/agents/writer-runtime.ps1') -Raw
foreach ($marker in @('Trusted runtime hash mismatch','Writer branch does not match lease','Writer execution: BLOCKED','required_command_type')) {
    if ($writerRuntimeSource -notmatch [regex]::Escape($marker)) {
        throw "Writer runtime preflight is missing required fail-closed marker: $marker"
    }
}
Write-Host '[OK] Trusted writer runtime policy, integrity gates, and canary boundaries validated.' -ForegroundColor Green

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
