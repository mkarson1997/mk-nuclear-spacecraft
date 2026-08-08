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

function Assert-NativeSuccess {
    param([Parameter(Mandatory=$true)][string]$Message)
    if (-not $?) { throw $Message }
}

$repoRoot = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if (-not $? -or -not $repoRoot) {
    throw 'Not inside a Git repository.'
}
$repoRoot = $repoRoot.Trim()

$repoName = Split-Path $repoRoot -Leaf
$worktreeRoot = Join-Path (Join-Path $HOME '.mk-spacecraft\worktrees') $repoName
$worktreeRootFull = [System.IO.Path]::GetFullPath($worktreeRoot).TrimEnd([char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
))

function Get-MKCurrentBranch {
    $branch = (git branch --show-current).Trim()
    if (-not $branch) { throw 'Detached HEAD is not supported for agent worktree management.' }
    return $branch
}

function ConvertTo-MKSlug {
    param([Parameter(Mandatory=$true)][string]$Value)

    # Worktree identifiers intentionally exclude dots. This keeps generated
    # directory and branch names simple and makes traversal tokens impossible.
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

function Get-MKWorktreePath {
    param([Parameter(Mandatory=$true)][string]$Slug)

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $worktreeRootFull $Slug))
    $requiredPrefix = $worktreeRootFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $candidate.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Worktree path escaped the managed root and was blocked: $candidate"
    }

    return $candidate
}

function Get-MKAgentBranch {
    param([Parameter(Mandatory=$true)][string]$Slug)
    return "agent-work/$Slug"
}

switch ($Action) {
    'status' {
        Write-Host "`n=== MK AGENT WORKTREES ===" -ForegroundColor Cyan
        Write-Host "Repository root : $repoRoot"
        Write-Host "Worktree root   : $worktreeRootFull"
        Write-Host ''
        git worktree list
        if (-not $?) { throw 'Failed to list Git worktrees.' }
        exit 0
    }

    'create' {
        if (-not $Name) { throw 'Name is required for create.' }

        $currentBranch = Get-MKCurrentBranch
        if ($currentBranch -in @('main','master')) {
            throw 'Agent worktree creation is blocked on main/master. Start a task branch first.'
        }

        $dirty = git status --porcelain
        if ($dirty) {
            throw 'Coordinator working tree is not clean. Checkpoint or discard changes before creating an agent worktree.'
        }

        $slug = ConvertTo-MKSlug $Name
        $path = Get-MKWorktreePath $slug
        $branch = Get-MKAgentBranch $slug

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

        New-Item -ItemType Directory -Path $worktreeRootFull -Force | Out-Null

        git worktree add -b $branch $path HEAD
        if (-not $?) {
            throw "Failed to create agent worktree: $path"
        }

        Write-Host "`n[MK] Agent worktree created." -ForegroundColor Green
        Write-Host "Coordinator : $currentBranch"
        Write-Host "Agent branch: $branch"
        Write-Host "Path        : $path"
        Write-Host "Engine      : $Engine"
        Write-Host "Role        : $Role"
        Write-Host 'Remote push : not performed during qualification.' -ForegroundColor Yellow
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

        if (-not (Test-Path $path)) {
            throw "Worktree path does not exist: $path"
        }

        $worktreeDirty = git -C $path status --porcelain
        if (-not $?) { throw "Failed to inspect worktree: $path" }
        if ($worktreeDirty) {
            throw 'Refusing to remove a dirty agent worktree.'
        }

        $currentBranch = Get-MKCurrentBranch
        git merge-base --is-ancestor $branch $currentBranch
        if (-not $?) {
            throw "Refusing to remove $branch because it contains commits not reachable from coordinator branch $currentBranch. Integrate or preserve them first."
        }

        git worktree remove $path
        if (-not $?) { throw "Failed to remove worktree: $path" }

        git branch -d $branch
        if (-not $?) { throw "Worktree removed, but safe branch deletion failed: $branch" }

        Write-Host "`n[MK] Agent worktree removed safely: $slug" -ForegroundColor Green
        exit 0
    }
}
