Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CommandVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Args = @('--version')
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return [pscustomobject]@{
            name = $Name
            installed = $false
            version = $null
            path = $null
        }
    }

    $versionText = $null
    try {
        $versionText = (& $Name @Args 2>&1 | Select-Object -First 3) -join ' | '
    }
    catch {
        $versionText = "version probe failed: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        name = $Name
        installed = $true
        version = $versionText
        path = $cmd.Source
    }
}

function Get-LatestGitHubRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Repository
    )

    $json = gh api "/repos/$Repository/releases/latest" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        return [pscustomobject]@{
            repository = $Repository
            ok = $false
            tag = $null
            published_at = $null
            html_url = $null
            assets = @()
        }
    }

    $release = $json | ConvertFrom-Json
    $assets = @($release.assets | ForEach-Object {
        [pscustomobject]@{
            name = $_.name
            size = $_.size
            digest = $_.digest
            url = $_.browser_download_url
        }
    })

    return [pscustomobject]@{
        repository = $Repository
        ok = $true
        tag = $release.tag_name
        published_at = $release.published_at
        html_url = $release.html_url
        assets = $assets
    }
}

Write-Host "`n=== MK SECURITY PHASE B PROBE ===" -ForegroundColor Cyan
Write-Host 'This script only reads local tool metadata and official GitHub release metadata.' -ForegroundColor DarkGray
Write-Host 'It does not install or modify any security tool.' -ForegroundColor DarkGray

Write-Host "`n=== LOCAL ENVIRONMENT ===" -ForegroundColor Cyan

$localTools = @(
    (Get-CommandVersion -Name 'gh'),
    (Get-CommandVersion -Name 'git'),
    (Get-CommandVersion -Name 'python'),
    (Get-CommandVersion -Name 'py'),
    (Get-CommandVersion -Name 'pipx'),
    (Get-CommandVersion -Name 'wsl'),
    (Get-CommandVersion -Name 'docker'),
    (Get-CommandVersion -Name 'cargo'),
    (Get-CommandVersion -Name 'gitleaks'),
    (Get-CommandVersion -Name 'trivy'),
    (Get-CommandVersion -Name 'semgrep'),
    (Get-CommandVersion -Name 'zizmor')
)

$localTools | Format-Table -AutoSize

Write-Host "`n=== OFFICIAL RELEASE METADATA ===" -ForegroundColor Cyan

$repositories = @(
    'gitleaks/gitleaks',
    'aquasecurity/trivy',
    'semgrep/semgrep',
    'zizmorcore/zizmor'
)

$releases = @()
foreach ($repository in $repositories) {
    Write-Host "`n[$repository]" -ForegroundColor Yellow
    $release = Get-LatestGitHubRelease -Repository $repository
    $releases += $release

    if (-not $release.ok) {
        Write-Host 'Unable to resolve latest release through GitHub API.' -ForegroundColor Red
        continue
    }

    Write-Host "Tag       : $($release.tag)"
    Write-Host "Published : $($release.published_at)"
    Write-Host "Release   : $($release.html_url)"

    if ($release.assets.Count -eq 0) {
        Write-Host 'Assets    : none exposed on the GitHub release'
        continue
    }

    $windowsAssets = @($release.assets | Where-Object {
        $_.name -match '(?i)(windows|win64|win_amd64|x86_64-pc-windows|amd64\.zip|windows_x86_64)'
    })

    if ($windowsAssets.Count -gt 0) {
        Write-Host 'Windows-looking assets:'
        $windowsAssets | Select-Object name, size, digest | Format-Table -AutoSize
    }
    else {
        Write-Host 'Windows-looking assets: none detected'
    }
}

Write-Host "`n=== WSL DISTRIBUTIONS ===" -ForegroundColor Cyan
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    try {
        wsl --list --verbose
    }
    catch {
        Write-Host "WSL probe failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host 'WSL command not installed.' -ForegroundColor Yellow
}

Write-Host "`n=== RESULT ===" -ForegroundColor Cyan
Write-Host 'Probe complete. No tools were installed or changed.' -ForegroundColor Green
Write-Host 'Use this output to pin versions and choose native Windows vs WSL installation paths safely.'
