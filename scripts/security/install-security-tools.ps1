Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lockPath = Join-Path $repoRoot 'registry\security-lock.json'

if (-not (Test-Path $lockPath)) {
    throw "Security lock file not found: $lockPath"
}

$lock = Get-Content $lockPath -Raw | ConvertFrom-Json

$mkHome = Join-Path $HOME '.mk-spacecraft'
$binDir = Join-Path $mkHome 'bin'
$cacheDir = Join-Path $mkHome 'cache\security-tools'

New-Item -ItemType Directory -Path $binDir -Force | Out-Null
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

function Assert-Command {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $Name"
    }
}

function Resolve-Python311 {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        $resolved = (& py -3.11 -c "import sys; print(sys.executable)" 2>$null | Select-Object -First 1)
        $nativeOk = $?
        if ($nativeOk -and $resolved) {
            $resolved = $resolved.Trim()
            if (Test-Path $resolved) { return $resolved }
        }
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        $resolved = (& python -c "import sys; assert sys.version_info[:2] == (3, 11); print(sys.executable)" 2>$null | Select-Object -First 1)
        $nativeOk = $?
        if ($nativeOk -and $resolved) {
            $resolved = $resolved.Trim()
            if (Test-Path $resolved) { return $resolved }
        }
    }

    throw 'Python 3.11 could not be resolved through py -3.11 or python.'
}

function Ensure-Pipx {
    param([Parameter(Mandatory=$true)][string]$PythonPath)

    $expected = $lock.bootstrap.pipx.version
    $pipxCommand = Get-Command pipx -ErrorAction SilentlyContinue
    if ($pipxCommand) {
        $current = (& pipx --version 2>$null | Select-Object -First 1)
        $nativeOk = $?
        if ($nativeOk -and $current -match [regex]::Escape($expected)) {
            return
        }
    }

    Write-Host "[MK] Bootstrapping pinned pipx==$expected..." -ForegroundColor Cyan
    & $PythonPath -m pip install --disable-pip-version-check --no-input --upgrade "pipx==$expected"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install pinned pipx==$expected"
    }

    $pythonScripts = Join-Path (Split-Path $PythonPath -Parent) 'Scripts'
    if ((Test-Path $pythonScripts) -and (($env:Path -split ';') -notcontains $pythonScripts)) {
        $env:Path = "$pythonScripts;$env:Path"
    }

    if (-not (Get-Command pipx -ErrorAction SilentlyContinue)) {
        throw 'pipx installation completed but pipx command is still unavailable.'
    }
}

function Install-GitHubReleaseBinary {
    param(
        [Parameter(Mandatory=$true)]$Tool
    )

    $assetPath = Join-Path $cacheDir $Tool.asset
    $extractDir = Join-Path $cacheDir ("extract-" + $Tool.repository.Replace('/', '-'))

    if (Test-Path $assetPath) {
        Remove-Item $assetPath -Force
    }
    if (Test-Path $extractDir) {
        Remove-Item $extractDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    Write-Host "[MK] Downloading $($Tool.repository) $($Tool.tag) from GitHub..." -ForegroundColor Cyan
    gh release download $Tool.tag --repo $Tool.repository --pattern $Tool.asset --dir $cacheDir --clobber
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $assetPath)) {
        throw "Download failed for $($Tool.repository) / $($Tool.asset)"
    }

    $actualHash = (Get-FileHash -Path $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedHash = $Tool.sha256.ToLowerInvariant()

    if ($actualHash -ne $expectedHash) {
        Remove-Item $assetPath -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $($Tool.asset). Expected $expectedHash but got $actualHash"
    }

    Write-Host "[MK] SHA-256 verified: $actualHash" -ForegroundColor Green

    Expand-Archive -Path $assetPath -DestinationPath $extractDir -Force

    $exe = Get-ChildItem -Path $extractDir -Filter $Tool.executable -File -Recurse | Select-Object -First 1
    if (-not $exe) {
        throw "Executable $($Tool.executable) not found after extraction."
    }

    Copy-Item $exe.FullName (Join-Path $binDir $Tool.executable) -Force
    Write-Host "[MK] Installed $($Tool.executable) into $binDir" -ForegroundColor Green
}

function Install-PipxTool {
    param(
        [Parameter(Mandatory=$true)]$Tool,
        [Parameter(Mandatory=$true)][string]$PythonPath
    )

    $spec = "$($Tool.package)==$($Tool.version)"
    Write-Host "[MK] Installing pinned PyPI package with pipx: $spec" -ForegroundColor Cyan

    $existing = pipx list --short 2>$null | Select-String -Pattern ("^" + [regex]::Escape($Tool.package) + " ")
    if ($existing) {
        pipx uninstall $Tool.package | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove existing pipx installation for $($Tool.package)."
        }
    }

    pipx install $spec --python $PythonPath
    if ($LASTEXITCODE -ne 0) {
        throw "pipx installation failed for $spec"
    }
}

Assert-Command 'gh'

Write-Host "`n=== MK SECURITY PHASE B INSTALL ===" -ForegroundColor Cyan
Write-Host "Install root : $mkHome"
Write-Host "Binary path  : $binDir"
Write-Host "Lock file    : $lockPath"

if ($lock.platform -ne 'windows-amd64') {
    throw "This installer only supports the locked platform windows-amd64. Found: $($lock.platform)"
}

$python311 = Resolve-Python311
Write-Host "Python 3.11 : $python311"
Ensure-Pipx -PythonPath $python311

Install-GitHubReleaseBinary -Tool $lock.tools.gitleaks
Install-GitHubReleaseBinary -Tool $lock.tools.trivy
Install-PipxTool -Tool $lock.tools.semgrep -PythonPath $python311
Install-PipxTool -Tool $lock.tools.zizmor -PythonPath $python311

$currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$userPathParts = @($currentUserPath -split ';' | Where-Object { $_ })
if ($userPathParts -notcontains $binDir) {
    $newUserPath = (($userPathParts + $binDir) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    Write-Host "[MK] Added $binDir to the user PATH." -ForegroundColor Green
}

if (($env:Path -split ';') -notcontains $binDir) {
    $env:Path = "$binDir;$env:Path"
}

Write-Host "`n=== VERSION VERIFICATION ===" -ForegroundColor Cyan

$checks = @(
    @{ Name = 'gitleaks'; Expected = $lock.tools.gitleaks.version; Command = { gitleaks version } },
    @{ Name = 'trivy'; Expected = $lock.tools.trivy.version; Command = { trivy --version } },
    @{ Name = 'semgrep'; Expected = $lock.tools.semgrep.version; Command = { semgrep --version } },
    @{ Name = 'zizmor'; Expected = $lock.tools.zizmor.version; Command = { zizmor --version } }
)

foreach ($check in $checks) {
    $output = (& $check.Command 2>&1 | Select-Object -First 5) -join ' | '
    if ($LASTEXITCODE -ne 0) {
        throw "$($check.Name) version check failed: $output"
    }

    if ($output -notmatch [regex]::Escape($check.Expected)) {
        throw "$($check.Name) version mismatch. Expected $($check.Expected). Output: $output"
    }

    Write-Host ("[OK] {0,-10} {1}" -f $check.Name, $output) -ForegroundColor Green
}

Write-Host "`n[MK] Phase B security tool installation complete." -ForegroundColor Green
Write-Host 'Open a new PowerShell after this run so the persisted user PATH is inherited everywhere.'
