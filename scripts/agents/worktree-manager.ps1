param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('status','create','remove')]
    [string]$Action,

    [Parameter(Position=1)]
    [string]$Name,

    [Parameter(Position=2)]
    [string]$Engine = 'codex-cli',

    [Parameter(Position=3)]
    [string]$Role = 'implementer',

    [switch]$ConfirmRemove
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

$spacecraftRoot = Get-MKFullPath (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fleetPath = Join-Path $spacecraftRoot 'registry\agent-fleet.json'
if (-not (Test-Path $fleetPath -PathType Leaf)) {
    throw "Agent fleet registry not found: $fleetPath"
}
$fleet = Get-Content $fleetPath -Raw | ConvertFrom-Json

$repoRootRaw = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $? -or -not $repoRootRaw) {
    throw 'Not inside a Git repository.'
}
$repoRoot = Get-MKFullPath $repoRootRaw.Trim()
$repoName = Split-Path $repoRoot -Leaf

$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($repoRoot.ToLowerInvariant()))
    $repoHash = ([System.BitConverter]::ToString($repoHashBytes) -replace '-','').ToLowerInvariant().Substring(0, 12)
}
finally {
    $sha256.Dispose()
}
$repoKey = "$repoName-$repoHash"

$worktreeRoot = Get-MKFullPath (Join-Path (Join-Path $HOME '.mk-spacecraft\worktrees') $repoKey)
$leaseRoot = Get-MKFullPath (Join-Path (Join-Path $HOME '.mk-spacecraft\state\worktree-leases') $repoKey)
$lockRoot = Get-MKFullPath (Join-Path $HOME '.mk-spacecraft\locks')
$lockPath = Join-Path $lockRoot "$repoKey.worktrees.lock"

function Get-MKCurrentBranch {
    $branch = (git branch --show-current).Trim()
    if (-not $branch) {
        throw 'Detached HEAD is not supported for agent worktree management.'
    }
    return $branch
}

function ConvertTo-MKSlug {
    param([Parameter(Mandatory=$true)][string]$Value)

    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9_-]+','-'
    $slug = $slug.Trim('-','_')

    if (-not $slug) {
        throw 'Name produced an empty worktree slug.'
    }
    if ($slug.Length -gt 80) {
        throw 'Worktree slug is too long. Keep the name under 80 normalized characters.'
    }
    if ($slug -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        throw "Unsafe worktree slug rejected: $slug"
    }

    return $slug
}

function Get-MKContainedPath {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Child,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $candidate = Get-MKFullPath (Join-Path $Root $Child)
    $requiredPrefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label escaped its managed root and was blocked: $candidate"
    }
    return $candidate
}

function Get-MKWorktreePath {
    param([Parameter(Mandatory=$true)][string]$Slug)
    return Get-MKContainedPath -Root $worktreeRoot -Child $Slug -Label 'Worktree path'
}

function Get-MKLeasePath {
    param([Parameter(Mandatory=$true)][string]$Slug)
    return Get-MKContainedPath -Root $leaseRoot -Child "$Slug.json" -Label 'Lease path'
}

function Get-MKAgentBranch {
    param([Parameter(Mandatory=$true)][string]$Slug)
    return "agent-work/$Slug"
}

function Assert-MKWriterAssignment {
    param(
        [Parameter(Mandatory=$true)][string]$EngineName,
        [Parameter(Mandatory=$true)][string]$RoleName
    )

    $engineProperty = $fleet.engines.PSObject.Properties[$EngineName]
    if (-not $engineProperty) {
        throw "Unknown agent engine: $EngineName"
    }

    if (-not (@($engineProperty.Value.roles) -contains $RoleName)) {
        throw "Engine '$EngineName' is not authorized for role '$RoleName'."
    }

    $roleProperty = $fleet.roles.PSObject.Properties[$RoleName]
    if (-not $roleProperty) {
        throw "Unknown agent role: $RoleName"
    }

    if ($roleProperty.Value.write_repository -ne $true) {
        throw "Role '$RoleName' is read-only and cannot own a writer worktree."
    }
    if ($roleProperty.Value.isolated_worktree -ne $true) {
        throw "Writer role '$RoleName' is missing the isolated-worktree requirement."
    }
    if ($roleProperty.Value.production_access -ne $false) {
        throw "Writer worktree role '$RoleName' must not imply production access."
    }
    if ($engineProperty.Value.default_write -ne $true) {
        throw "Engine '$EngineName' is not registered as writer-capable."
    }
}

function Enter-MKWorktreeLock {
    New-Item -ItemType Directory -Path $lockRoot -Force | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(8)

    while ($true) {
        try {
            return [System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
        }
        catch [System.IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) {
                throw "Timed out waiting for the atomic worktree lease lock: $lockPath"
            }
            Start-Sleep -Milliseconds 125
        }
    }
}

function Write-MKLeaseAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Lease
    )

    New-Item -ItemType Directory -Path $leaseRoot -Force | Out-Null
    $tempPath = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Lease | ConvertTo-Json -Depth 8 | Set-Content -Path $tempPath -Encoding utf8NoBOM
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Read-MKLease {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Active writer lease not found: $Path"
    }
    $lease = Get-Content $Path -Raw | ConvertFrom-Json
    if ($lease.schema -ne 1 -or $lease.status -ne 'active') {
        throw "Writer lease is invalid or not active: $Path"
    }
    return $lease
}

switch ($Action) {
    'status' {
        Write-Host "`n=== MK AGENT WORKTREES ===" -ForegroundColor Cyan
        Write-Host "Repository root : $repoRoot"
        Write-Host "Repository key  : $repoKey"
        Write-Host "Worktree root   : $worktreeRoot"
        Write-Host "Lease root      : $leaseRoot"
        Write-Host ''

        git worktree list
        if (-not $?) { throw 'Failed to list Git worktrees.' }

        Write-Host "`n=== ACTIVE WRITER LEASES ===" -ForegroundColor Cyan
        $leaseFiles = @()
        if (Test-Path $leaseRoot) {
            $leaseFiles = @(Get-ChildItem -Path $leaseRoot -Filter '*.json' -File | Sort-Object Name)
        }

        if ($leaseFiles.Count -eq 0) {
            Write-Host 'None.' -ForegroundColor Yellow
        }
        else {
            foreach ($leaseFile in $leaseFiles) {
                try {
                    $lease = Read-MKLease $leaseFile.FullName
                    Write-Host "[$($lease.slug)] $($lease.engine)/$($lease.role) -> $($lease.branch)"
                    Write-Host "  Path : $($lease.path)"
                    Write-Host "  Lease: $($lease.lease_id)"
                }
                catch {
                    Write-Host "[INVALID LEASE] $($leaseFile.FullName): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        exit 0
    }

    'create' {
        if (-not $Name) { throw 'Name is required for create.' }
        Assert-MKWriterAssignment -EngineName $Engine -RoleName $Role

        $currentBranch = Get-MKCurrentBranch
        if ($currentBranch -in @('main','master')) {
            throw 'Agent worktree creation is blocked on main/master. Start a task branch first.'
        }

        $dirty = git status --porcelain
        if ($dirty) {
            throw 'Coordinator working tree is not clean. Checkpoint or discard changes before creating an agent worktree.'
        }

        $coordinatorHead = (git rev-parse HEAD).Trim()
        if (-not $?) { throw 'Failed to resolve coordinator HEAD.' }

        $slug = ConvertTo-MKSlug $Name
        $path = Get-MKWorktreePath $slug
        $branch = Get-MKAgentBranch $slug
        $leasePath = Get-MKLeasePath $slug
        $lockHandle = Enter-MKWorktreeLock

        try {
            if (Test-Path $leasePath) {
                throw "An active or stale writer lease already exists for '$slug': $leasePath"
            }
            if (Test-Path $path) {
                throw "Worktree path already exists: $path"
            }

            git show-ref --verify --quiet "refs/heads/$branch"
            if ($?) {
                throw "Local agent branch already exists: $branch"
            }

            git ls-remote --exit-code --heads origin $branch *> $null
            if ($?) {
                throw "Remote agent branch already exists: $branch"
            }

            New-Item -ItemType Directory -Path $worktreeRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $leaseRoot -Force | Out-Null

            git worktree add -b $branch $path HEAD
            if (-not $?) {
                throw "Failed to create agent worktree: $path"
            }

            $lease = [ordered]@{
                schema = 1
                status = 'active'
                lease_id = [Guid]::NewGuid().ToString('D')
                repo_key = $repoKey
                repo_root = $repoRoot
                slug = $slug
                path = $path
                branch = $branch
                engine = $Engine
                role = $Role
                coordinator_branch = $currentBranch
                coordinator_head = $coordinatorHead
                created_at_utc = [DateTime]::UtcNow.ToString('o')
            }

            try {
                Write-MKLeaseAtomic -Path $leasePath -Lease $lease
            }
            catch {
                $leaseError = $_
                git worktree remove $path *> $null
                git branch -d $branch *> $null
                throw "Writer worktree was rolled back because its lease could not be persisted: $($leaseError.Exception.Message)"
            }

            Write-Host "`n[MK] Agent writer worktree leased." -ForegroundColor Green
            Write-Host "Coordinator : $currentBranch"
            Write-Host "Agent branch: $branch"
            Write-Host "Path        : $path"
            Write-Host "Engine      : $Engine"
            Write-Host "Role        : $Role"
            Write-Host "Lease       : $($lease.lease_id)"
            Write-Host "Lease file  : $leasePath"
            Write-Host 'Remote push : not performed during qualification.' -ForegroundColor Yellow
        }
        finally {
            $lockHandle.Dispose()
        }
        exit 0
    }

    'remove' {
        if (-not $Name) { throw 'Name is required for remove.' }
        if (-not $ConfirmRemove) {
            throw 'Removal requires explicit -ConfirmRemove.'
        }

        $slug = ConvertTo-MKSlug $Name
        $path = Get-MKWorktreePath $slug
        $branch = Get-MKAgentBranch $slug
        $leasePath = Get-MKLeasePath $slug
        $lockHandle = Enter-MKWorktreeLock

        try {
            $lease = Read-MKLease $leasePath
            Assert-MKWriterAssignment -EngineName ([string]$lease.engine) -RoleName ([string]$lease.role)

            if ([string]$lease.repo_key -ne $repoKey -or (Get-MKFullPath ([string]$lease.repo_root)) -ne $repoRoot) {
                throw 'Writer lease repository identity does not match the current repository.'
            }
            if ((Get-MKFullPath ([string]$lease.path)) -ne $path -or [string]$lease.branch -ne $branch) {
                throw 'Writer lease path/branch does not match the requested managed worktree.'
            }
            if (-not (Test-Path $path)) {
                throw "Worktree path does not exist: $path"
            }

            $worktreeDirty = git -C $path status --porcelain
            if (-not $?) { throw "Failed to inspect worktree: $path" }
            if ($worktreeDirty) {
                throw 'Refusing to remove a dirty agent worktree.'
            }

            $currentBranch = Get-MKCurrentBranch
            if ($currentBranch -ne [string]$lease.coordinator_branch) {
                throw "Lease belongs to coordinator branch '$($lease.coordinator_branch)', but current branch is '$currentBranch'."
            }

            git merge-base --is-ancestor $branch $currentBranch
            if (-not $?) {
                throw "Refusing to remove $branch because it contains commits not reachable from coordinator branch $currentBranch. Integrate or preserve them first."
            }

            git worktree remove $path
            if (-not $?) { throw "Failed to remove worktree: $path" }

            git branch -d $branch
            if (-not $?) { throw "Worktree removed, but safe branch deletion failed: $branch" }

            Remove-Item -LiteralPath $leasePath -Force
            Write-Host "`n[MK] Agent writer worktree and active lease removed safely: $slug" -ForegroundColor Green
        }
        finally {
            $lockHandle.Dispose()
        }
        exit 0
    }
}
