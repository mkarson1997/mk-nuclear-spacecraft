param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('status','install')]
    [string]$Action
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

function Assert-MKContainedPath {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Candidate,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $rootFull = Get-MKFullPath $Root
    $candidateFull = Get-MKFullPath $Candidate
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped the trusted runtime root: $candidateFull"
    }
    return $candidateFull
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $tmp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding utf8NoBOM
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

$repoRootRaw = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $? -or -not $repoRootRaw) { throw 'Not inside a Git repository.' }
$repoRoot = Get-MKFullPath $repoRootRaw.Trim()
$policyPath = Join-Path $repoRoot 'registry\agent-execution-policy.json'
if (-not (Test-Path $policyPath -PathType Leaf)) { throw "Execution policy missing: $policyPath" }
$policy = Get-Content $policyPath -Raw | ConvertFrom-Json
if ($policy.schema -ne 1) { throw "Unsupported execution policy schema: $($policy.schema)" }

$runtimeRoot = Get-MKFullPath (Join-Path (Join-Path $HOME '.mk-spacecraft\runtime') $policy.trusted_runtime.runtime_name)
$versionsRoot = Get-MKFullPath (Join-Path $runtimeRoot 'versions')
$activePath = Join-Path $runtimeRoot 'active.json'

if ($Action -eq 'status') {
    Write-Host "`n=== MK TRUSTED WRITER RUNTIME ===" -ForegroundColor Cyan
    Write-Host "Runtime root : $runtimeRoot"
    if (-not (Test-Path $activePath -PathType Leaf)) {
        Write-Host 'Active runtime: not installed' -ForegroundColor Yellow
        exit 0
    }

    $active = Get-Content $activePath -Raw | ConvertFrom-Json
    if ($active.schema -ne 1) { throw 'Unsupported active runtime pointer schema.' }
    $versionRoot = Assert-MKContainedPath -Root $versionsRoot -Candidate ([string]$active.version_root) -Label 'Active runtime version'
    if ((Split-Path $versionRoot -Leaf) -ne [string]$active.source_commit) {
        throw 'Active runtime directory does not match its source commit.'
    }

    $manifestPath = Join-Path $versionRoot 'runtime-manifest.json'
    if (-not (Test-Path $manifestPath -PathType Leaf)) { throw "Active runtime manifest missing: $manifestPath" }
    $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()
    if ($manifestHash -ne ([string]$active.manifest_sha256).ToLowerInvariant()) {
        throw 'Active runtime manifest hash does not match active.json.'
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.source_commit -ne $active.source_commit) {
        throw 'Active runtime manifest identity mismatch.'
    }

    foreach ($file in @($manifest.files)) {
        $candidate = Assert-MKContainedPath -Root $versionRoot -Candidate (Join-Path $versionRoot $file.name) -Label 'Trusted runtime file'
        if (-not (Test-Path $candidate -PathType Leaf)) { throw "Trusted runtime file missing: $candidate" }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
        if ($actual -ne ([string]$file.sha256).ToLowerInvariant()) {
            throw "Trusted runtime hash mismatch: $candidate"
        }
    }

    Write-Host "Active runtime : $($manifest.source_commit)" -ForegroundColor Green
    Write-Host "Installed UTC  : $($manifest.installed_at_utc)"
    Write-Host 'Manifest hash  : PASS' -ForegroundColor Green
    Write-Host 'File hashes    : PASS' -ForegroundColor Green
    exit 0
}

$branch = (git branch --show-current).Trim()
$requiredBranch = [string]$policy.trusted_runtime.install_from_branch
if ($branch -ne $requiredBranch) {
    throw "Trusted runtime installation is allowed only from '$requiredBranch'. Current branch: $branch"
}

if ($policy.trusted_runtime.require_clean_source -eq $true) {
    $dirty = @(git status --porcelain=v1)
    if (-not $?) { throw 'Failed to inspect source repository status.' }
    if ($dirty.Count -gt 0) { throw 'Trusted runtime source repository must be clean.' }
}

$head = (git rev-parse HEAD).Trim()
if (-not $?) { throw 'Failed to resolve source HEAD.' }
$originHead = (git rev-parse "refs/remotes/origin/$requiredBranch" 2>$null | Select-Object -First 1)
if (-not $? -or -not $originHead) { throw "Missing origin/$requiredBranch tracking ref. Fetch first." }
$originHead = $originHead.Trim()
if ($policy.trusted_runtime.require_head_equal_origin -eq $true -and $head -ne $originHead) {
    throw "Trusted runtime source HEAD must equal origin/$requiredBranch. HEAD=$head origin=$originHead"
}

if ($policy.trusted_runtime.require_remote_main_match -eq $true) {
    $remoteLine = (git ls-remote origin "refs/heads/$requiredBranch" 2>$null | Select-Object -First 1)
    if (-not $? -or -not $remoteLine) { throw "Failed to resolve remote refs/heads/$requiredBranch." }
    $remoteHead = ($remoteLine -split '\s+')[0]
    if ($remoteHead -ne $head) {
        throw "Remote $requiredBranch moved or local tracking state is stale. Remote=$remoteHead HEAD=$head"
    }
}

$sourceFiles = [ordered]@{
    'writer-runtime.ps1' = (Join-Path $repoRoot 'scripts\agents\writer-runtime.ps1')
    'agent-execution-policy.json' = $policyPath
    'agent-fleet.json' = (Join-Path $repoRoot 'registry\agent-fleet.json')
}
foreach ($entry in $sourceFiles.GetEnumerator()) {
    if (-not (Test-Path $entry.Value -PathType Leaf)) { throw "Trusted runtime source file missing: $($entry.Value)" }
}

$versionRoot = Assert-MKContainedPath -Root $versionsRoot -Candidate (Join-Path $versionsRoot $head) -Label 'Runtime installation path'
if (Test-Path $versionRoot) {
    throw "Trusted runtime version already exists: $versionRoot"
}
New-Item -ItemType Directory -Path $versionRoot -Force | Out-Null

$manifestFiles = @()
try {
    foreach ($entry in $sourceFiles.GetEnumerator()) {
        $destination = Assert-MKContainedPath -Root $versionRoot -Candidate (Join-Path $versionRoot $entry.Key) -Label 'Runtime destination'
        Copy-Item -LiteralPath $entry.Value -Destination $destination
        $manifestFiles += [ordered]@{
            name = $entry.Key
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
        }
    }

    $manifest = [ordered]@{
        schema = 1
        runtime_name = [string]$policy.trusted_runtime.runtime_name
        source_repo = $repoRoot
        source_branch = $branch
        source_commit = $head
        installed_at_utc = [DateTime]::UtcNow.ToString('o')
        files = $manifestFiles
    }
    $manifestPath = Join-Path $versionRoot 'runtime-manifest.json'
    Write-JsonAtomic -Path $manifestPath -Value $manifest
    $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToLowerInvariant()

    $active = [ordered]@{
        schema = 1
        runtime_name = [string]$policy.trusted_runtime.runtime_name
        source_commit = $head
        version_root = $versionRoot
        manifest_sha256 = $manifestHash
        activated_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-JsonAtomic -Path $activePath -Value $active
}
catch {
    if (Test-Path $versionRoot) { Remove-Item -LiteralPath $versionRoot -Recurse -Force }
    throw
}

Write-Host "`n[MK] Trusted writer runtime installed." -ForegroundColor Green
Write-Host "Source commit : $head"
Write-Host "Runtime path  : $versionRoot"
Write-Host "Active pointer: $activePath"
Write-Host 'Writer execution remains disabled by policy.' -ForegroundColor Yellow
