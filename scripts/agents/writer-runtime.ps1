param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('status','preflight')]
    [string]$Action,

    [Parameter(Position=1)]
    [string]$RepoRoot,

    [Parameter(Position=2)]
    [string]$LeaseSlug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MKFullPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ))
}

function Get-RepoKey {
    param([Parameter(Mandatory=$true)][string]$Root)
    $name = Split-Path $Root -Leaf
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))
        $hash = ([System.BitConverter]::ToString($bytes) -replace '-','').ToLowerInvariant().Substring(0, 12)
    }
    finally {
        $sha256.Dispose()
    }
    return "$name-$hash"
}

$scriptPath = Get-MKFullPath $PSCommandPath
$runtimeVersionRoot = Get-MKFullPath $PSScriptRoot
$runtimeRootExpected = Get-MKFullPath (Join-Path $HOME '.mk-spacecraft\runtime\writer-core\versions')
$runtimePrefix = $runtimeRootExpected + [System.IO.Path]::DirectorySeparatorChar
if (-not $runtimeVersionRoot.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Writer runtime must execute from the trusted external runtime tree. Current path: $runtimeVersionRoot"
}

$manifestPath = Join-Path $runtimeVersionRoot 'runtime-manifest.json'
$policyPath = Join-Path $runtimeVersionRoot 'agent-execution-policy.json'
$fleetPath = Join-Path $runtimeVersionRoot 'agent-fleet.json'
foreach ($required in @($manifestPath,$policyPath,$fleetPath)) {
    if (-not (Test-Path $required -PathType Leaf)) { throw "Trusted runtime file missing: $required" }
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$policy = Get-Content $policyPath -Raw | ConvertFrom-Json
$fleet = Get-Content $fleetPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $policy.schema -ne 1 -or $fleet.schema -ne 1) {
    throw 'Unsupported trusted runtime schema.'
}
foreach ($file in @($manifest.files)) {
    $candidate = Join-Path $runtimeVersionRoot $file.name
    if (-not (Test-Path $candidate -PathType Leaf)) { throw "Trusted runtime file missing: $candidate" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$file.sha256).ToLowerInvariant()) { throw "Trusted runtime hash mismatch: $candidate" }
}

if ($Action -eq 'status') {
    Write-Host "`n=== MK TRUSTED WRITER PREFLIGHT ===" -ForegroundColor Cyan
    Write-Host "Runtime commit : $($manifest.source_commit)"
    Write-Host "Runtime path   : $runtimeVersionRoot"
    Write-Host "Writer execute : $($policy.project_writer_execution_enabled)"
    Write-Host "Qualification  : $($policy.writer_qualification_enabled)"
    Write-Host 'Runtime hashes : PASS' -ForegroundColor Green
    exit 0
}

if (-not $RepoRoot) { throw 'RepoRoot is required for preflight.' }
if (-not $LeaseSlug) { throw 'LeaseSlug is required for preflight.' }
$RepoRoot = Get-MKFullPath $RepoRoot
if (-not (Test-Path $RepoRoot -PathType Container)) { throw "Repository root does not exist: $RepoRoot" }

$repoKey = Get-RepoKey $RepoRoot
$leaseRoot = Get-MKFullPath (Join-Path (Join-Path $HOME '.mk-spacecraft\state\worktree-leases') $repoKey)
if ($LeaseSlug -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw "Unsafe lease slug: $LeaseSlug" }
$leasePath = Get-MKFullPath (Join-Path $leaseRoot "$LeaseSlug.json")
$leasePrefix = $leaseRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $leasePath.StartsWith($leasePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Lease path escaped the managed lease root.'
}
if (-not (Test-Path $leasePath -PathType Leaf)) { throw "Active writer lease not found: $leasePath" }
$lease = Get-Content $leasePath -Raw | ConvertFrom-Json
if ($lease.schema -ne 1 -or $lease.status -ne 'active') { throw 'Writer lease is invalid or inactive.' }
if ((Get-MKFullPath $lease.repo_root) -ne $RepoRoot) { throw 'Writer lease repository root mismatch.' }
if ($lease.repo_key -ne $repoKey) { throw 'Writer lease repository key mismatch.' }

$expectedEngine = [string]$policy.writer.qualification_engine
$expectedRole = [string]$policy.writer.qualification_role
if ($lease.engine -ne $expectedEngine) { throw "Qualification lease engine must be '$expectedEngine'." }
if ($lease.role -ne $expectedRole) { throw "Qualification lease role must be '$expectedRole'." }

$engineProp = $fleet.engines.PSObject.Properties[$lease.engine]
$roleProp = $fleet.roles.PSObject.Properties[$lease.role]
if (-not $engineProp -or -not $roleProp) { throw 'Lease engine or role is absent from trusted fleet registry.' }
if (-not (@($engineProp.Value.roles) -contains $lease.role)) { throw 'Lease engine-role pair is not authorized by the trusted fleet registry.' }
if ($engineProp.Value.default_write -ne $true -or $roleProp.Value.write_repository -ne $true -or $roleProp.Value.isolated_worktree -ne $true) {
    throw 'Lease is not authorized for isolated writer execution.'
}
if ($roleProp.Value.production_access -ne $false) { throw 'Writer role must not imply production access.' }

$worktreePath = Get-MKFullPath $lease.path
if (-not (Test-Path $worktreePath -PathType Container)) { throw "Leased worktree path does not exist: $worktreePath" }
$actualTop = (git -C $worktreePath rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $? -or -not $actualTop) { throw 'Leased path is not a Git worktree.' }
if ((Get-MKFullPath $actualTop.Trim()) -ne $worktreePath) { throw 'Leased path does not equal Git worktree root.' }

$branch = (git -C $worktreePath branch --show-current).Trim()
if (-not $branch) { throw 'Writer worktree is detached.' }
if ($branch -ne [string]$lease.branch) { throw "Writer branch does not match lease. Branch=$branch Lease=$($lease.branch)" }
$prefix = [string]$policy.writer.required_branch_prefix
if (-not $branch.StartsWith($prefix, [System.StringComparison]::Ordinal)) { throw "Writer branch is outside required namespace '$prefix'." }
if (@($policy.writer.forbidden_branches) -contains $branch) { throw "Protected branch is forbidden for writer execution: $branch" }

if ($policy.writer.require_clean_worktree -eq $true) {
    $dirty = @(git -C $worktreePath status --porcelain=v1)
    if (-not $?) { throw 'Failed to inspect writer worktree state.' }
    if ($dirty.Count -gt 0) { throw 'Writer worktree must be clean before launch.' }
}
if ($policy.writer.require_clean_coordinator -eq $true) {
    $coordinatorDirty = @(git -C $RepoRoot status --porcelain=v1)
    if (-not $?) { throw 'Failed to inspect coordinator state.' }
    if ($coordinatorDirty.Count -gt 0) { throw 'Coordinator worktree must be clean before writer launch.' }
    $coordinatorBranch = (git -C $RepoRoot branch --show-current).Trim()
    if ($coordinatorBranch -ne [string]$lease.coordinator_branch) {
        throw "Coordinator branch changed since lease creation. Current=$coordinatorBranch Lease=$($lease.coordinator_branch)"
    }
}

$commandName = [string]$engineProp.Value.command
$command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $command) { throw "Writer engine executable not found: $commandName" }
if ([string]$command.CommandType -ne [string]$policy.trusted_runtime.required_command_type) {
    throw "Writer engine must resolve to CommandType '$($policy.trusted_runtime.required_command_type)'. Actual: $($command.CommandType)"
}
$executablePath = Get-MKFullPath $command.Source
$requiredExtension = [string]$policy.trusted_runtime.required_executable_extension
if (-not $executablePath.EndsWith($requiredExtension, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Writer engine executable must end with '$requiredExtension'. Path: $executablePath"
}
$executableHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $executablePath).Hash.ToLowerInvariant()

if ($policy.project_writer_execution_enabled -ne $false) {
    throw 'Unexpected policy state: project writer execution must remain disabled during preflight qualification.'
}
if ($policy.writer_qualification_enabled -ne $false) {
    throw 'Unexpected policy state: writer qualification execution is not yet allowed in this layer.'
}

Write-Host "`n[PASS] Trusted writer preflight succeeded." -ForegroundColor Green
Write-Host "Runtime commit : $($manifest.source_commit)"
Write-Host "Lease          : $($lease.lease_id)"
Write-Host "Engine/Role    : $($lease.engine)/$($lease.role)"
Write-Host "Worktree       : $worktreePath"
Write-Host "Branch         : $branch"
Write-Host "Executable     : $executablePath"
Write-Host "Executable SHA : $executableHash"
Write-Host 'Writer execution: BLOCKED' -ForegroundColor Yellow
