Set-StrictMode -Version Latest

function Assert-MKGitRepo {
    $inside = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
        throw 'Not inside a Git repository.'
    }
}

function Get-MKBranch {
    return (git branch --show-current).Trim()
}

function mk-status {
    Assert-MKGitRepo

    $root = (git rev-parse --show-toplevel).Trim()
    $branch = Get-MKBranch
    $remote = git remote get-url origin 2>$null

    Write-Host "`n=== MK PROJECT STATUS ===" -ForegroundColor Cyan
    Write-Host "Repo   : $root"
    Write-Host "Branch : $branch"
    if ($remote) { Write-Host "Origin : $remote" }

    git fetch origin --prune --quiet 2>$null
    git status -sb
    git log -1 --pretty=format:"Last commit: %h %s (%cr)"
    Write-Host ''

    $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $upstream) {
        $counts = git rev-list --left-right --count "HEAD...$upstream"
        Write-Host "Ahead/behind vs $upstream : $counts"
    } else {
        Write-Host 'Upstream: not configured' -ForegroundColor Yellow
    }
}

function mk-start-task {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateSet('feature','fix','chore','docs','agent','bootstrap')]
        [string]$Type,

        [Parameter(Mandatory=$true, Position=1)]
        [string]$Name
    )

    Assert-MKGitRepo

    $dirty = git status --porcelain
    if ($dirty) {
        throw 'Working tree is not clean. Commit, checkpoint, or stash current work first.'
    }

    $current = Get-MKBranch
    if ($current -ne 'main') {
        throw "Start new tasks from main. Current branch: $current"
    }

    $slug = $Name.ToLowerInvariant() -replace '[^a-z0-9._-]+','-'
    $slug = $slug.Trim('-')
    if (-not $slug) { throw 'Task name produced an empty branch name.' }

    $branch = "$Type/$slug"

    git fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch origin/main.' }

    git pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fast-forward main.' }

    git show-ref --verify --quiet "refs/heads/$branch"
    if ($LASTEXITCODE -eq 0) { throw "Local branch already exists: $branch" }

    git ls-remote --exit-code --heads origin $branch *> $null
    if ($LASTEXITCODE -eq 0) { throw "Remote branch already exists: $branch" }

    git switch -c $branch
    if ($LASTEXITCODE -ne 0) { throw "Failed to create branch: $branch" }

    git push -u origin $branch
    if ($LASTEXITCODE -ne 0) { throw "Branch created locally but initial push failed: $branch" }

    Write-Host "`n[MK] Task started safely: $branch" -ForegroundColor Green
}

function mk-checkpoint {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message
    )

    Assert-MKGitRepo

    $branch = Get-MKBranch
    if ($branch -in @('main','master')) {
        throw 'Checkpoint blocked on main/master. Work on a task branch.'
    }

    $changes = git status --porcelain
    if (-not $changes) {
        Write-Host '[MK] Nothing to checkpoint.' -ForegroundColor Yellow
        return
    }

    $root = (git rev-parse --show-toplevel).Trim()
    $verify = Join-Path $root 'scripts\verify.ps1'

    if (Test-Path $verify) {
        Write-Host '[MK] Running project verification...' -ForegroundColor Cyan
        & $verify
        if ($LASTEXITCODE -ne 0) {
            throw 'Project verification failed. Nothing was committed.'
        }
    }

    git add -A
    if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }

    $stagedFiles = @(git diff --cached --name-only)
    $secretFilePattern = '(?i)(^|/)\.env($|\.)|\.pem$|\.key$|\.p12$|\.pfx$|(^|/)(credentials|secrets)(\.|/|$)|(^|/)auth\.json$'
    $blockedFiles = @($stagedFiles | Where-Object { $_ -match $secretFilePattern -and $_ -notmatch '(?i)\.env\.example$' })

    if ($blockedFiles.Count -gt 0) {
        git reset --quiet
        Write-Host '[MK] Possible secret files detected:' -ForegroundColor Red
        $blockedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        throw 'Checkpoint blocked before commit.'
    }

    $diffText = git diff --cached --no-color --unified=0
    $secretContentPattern = '(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}'
    if (($diffText -join "`n") -match $secretContentPattern) {
        git reset --quiet
        throw 'Checkpoint blocked: staged diff contains text resembling a credential or private key.'
    }

    git diff --cached --check
    if ($LASTEXITCODE -ne 0) {
        git reset --quiet
        throw 'git diff --check failed. Fix whitespace/conflict-marker issues first.'
    }

    git commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }

    git push
    if ($LASTEXITCODE -ne 0) { throw 'Commit succeeded locally, but push failed.' }

    Write-Host "`n[MK] Checkpoint committed and pushed to GitHub." -ForegroundColor Green
    git log -1 --oneline
}

Export-ModuleMember -Function mk-status, mk-start-task, mk-checkpoint
