param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('quick','full','nuclear')]
    [string]$Mode,

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

    throw "Required security tool is missing: $Name. Run scripts/security/install-security-tools.ps1 first."
}

function Invoke-MKStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Action
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$Name failed with exit code $code."
    }
    Write-Host "[OK] $Name" -ForegroundColor Green
}

if (-not $RepositoryRoot) {
    $RepositoryRoot = (git rev-parse --show-toplevel 2>$null).Trim()
}

if (-not $RepositoryRoot -or -not (Test-Path $RepositoryRoot)) {
    throw 'mk-security must run inside a Git repository.'
}

$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path
$repoName = Split-Path $RepositoryRoot -Leaf
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportRoot = Join-Path (Join-Path $HOME '.mk-spacecraft\reports') (Join-Path $repoName $stamp)
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

$gitleaks = Resolve-MKSecurityTool -Name 'gitleaks'
$trivy = Resolve-MKSecurityTool -Name 'trivy'
$semgrep = Resolve-MKSecurityTool -Name 'semgrep'
$zizmor = Resolve-MKSecurityTool -Name 'zizmor'

Write-Host "`n=== MK SECURITY: $($Mode.ToUpperInvariant()) ===" -ForegroundColor Magenta
Write-Host "Repository : $RepositoryRoot"
Write-Host "Reports    : $reportRoot"

Push-Location $RepositoryRoot
try {
    Invoke-MKStep -Name 'Git whitespace/conflict sanity' -Action {
        git diff --check
    }

    Invoke-MKStep -Name 'Gitleaks working-tree scan' -Action {
        & $gitleaks dir $RepositoryRoot --no-banner --redact=100 --report-format json --report-path (Join-Path $reportRoot 'gitleaks-working-tree.json')
    }

    if ($Mode -eq 'quick') {
        Write-Host "`n[MK] QUICK security scan passed." -ForegroundColor Green
        Write-Host "Reports: $reportRoot"
        exit 0
    }

    Invoke-MKStep -Name 'Trivy filesystem security scan' -Action {
        & $trivy fs --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --exit-code 1 --no-progress $RepositoryRoot
    }

    Invoke-MKStep -Name 'Semgrep SAST' -Action {
        # Use an explicit official Community ruleset so metrics can remain disabled.
        # --oss-only prevents accidental use of managed/proprietary engines.
        & $semgrep scan --config p/default --oss-only --error --metrics=off $RepositoryRoot
    }

    $workflowDir = Join-Path $RepositoryRoot '.github\workflows'
    if (Test-Path $workflowDir) {
        Invoke-MKStep -Name 'zizmor CI/CD security scan' -Action {
            & $zizmor $RepositoryRoot
        }
    }
    else {
        Write-Host "`n[SKIP] zizmor: no .github/workflows directory." -ForegroundColor Yellow
    }

    if ($Mode -eq 'full') {
        Write-Host "`n[MK] FULL security scan passed." -ForegroundColor Green
        Write-Host "Reports: $reportRoot"
        exit 0
    }

    Invoke-MKStep -Name 'Gitleaks full Git-history scan' -Action {
        & $gitleaks git $RepositoryRoot --no-banner --redact=100 --report-format json --report-path (Join-Path $reportRoot 'gitleaks-history.json')
    }

    Invoke-MKStep -Name 'CycloneDX SBOM generation' -Action {
        & $trivy fs --format cyclonedx --output (Join-Path $reportRoot 'sbom.cdx.json') --no-progress $RepositoryRoot
    }

    @'
NUCLEAR MODE completed the currently automated gates:
- working-tree secret scan
- Git history secret scan
- Trivy vulnerability/secret/misconfiguration scan
- Semgrep Community SAST with explicit p/default ruleset and metrics disabled
- zizmor CI/CD analysis when workflows exist
- CycloneDX SBOM generation

Not yet automated in this phase:
- OWASP ASVS guided review
- threat model
- attack-surface map
- ZAP staging DAST
- second-agent security review
- supply-chain provenance/signing verification
'@ | Set-Content (Join-Path $reportRoot 'NUCLEAR-NEXT-GATES.txt') -Encoding utf8

    Write-Host "`n[MK] NUCLEAR automated security scan passed." -ForegroundColor Green
    Write-Host 'Manual/agent-assisted nuclear gates are listed in NUCLEAR-NEXT-GATES.txt.' -ForegroundColor Yellow
    Write-Host "Reports: $reportRoot"
}
finally {
    Pop-Location
}
