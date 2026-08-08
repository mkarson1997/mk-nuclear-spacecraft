param(
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-MKSecurityTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $fallback = Join-Path (Join-Path $HOME '.mk-spacecraft\bin') "$Name.exe"
    if (Test-Path $fallback) {
        return $fallback
    }

    throw "Required security tool is missing: $Name"
}

if (-not $RepositoryRoot) {
    $RepositoryRoot = (git rev-parse --show-toplevel 2>$null).Trim()
}

if (-not $RepositoryRoot -or -not (Test-Path $RepositoryRoot)) {
    throw 'Unable to resolve repository root for staged secret scan.'
}

$gitleaks = Resolve-MKSecurityTool -Name 'gitleaks'
$tempRoot = Join-Path $RepositoryRoot ('.tmp\mk-staged-' + [guid]::NewGuid().ToString('N'))
$prefix = ($tempRoot -replace '\\','/') + '/'

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    git checkout-index --all --prefix=$prefix
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to materialize the staged Git index for security scanning.'
    }

    Write-Host '[MK] Gitleaks: scanning exact staged repository snapshot...' -ForegroundColor Cyan
    & $gitleaks dir $tempRoot --no-banner --redact=100 --exit-code 1
    $scanExit = $LASTEXITCODE

    if ($scanExit -ne 0) {
        throw 'Gitleaks detected a possible secret in the staged repository snapshot.'
    }

    Write-Host '[OK] Staged secret scan passed.' -ForegroundColor Green
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
