param(
    [string]$RepoUrl = "https://github.com/seymour-ai/seymour-fleet.git",
    [string]$Branch = "main",
    [string]$InstallRoot = "",
    [string]$RepoPath = "",
    [string]$TargetHost = $env:COMPUTERNAME,
    [string]$StateDir = "",
    [switch]$WriteState,
    [switch]$NoInstall,
    [switch]$SkipRepoUpdate
)

$ErrorActionPreference = "Stop"

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-NativeCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $output = & $Command @Arguments 2>&1
    return $LASTEXITCODE -eq 0
}

function Test-UsablePython {
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "python"
    )

    foreach ($candidate in $candidates) {
        if (((Test-Path $candidate) -or (Test-Command $candidate)) -and (Test-NativeCommand -Command $candidate -Arguments @("--version"))) {
            return $true
        }
    }

    if (Test-Command "py") {
        return Test-NativeCommand -Command "py" -Arguments @("-3", "--version")
    }

    return $false
}

function Add-CommonToolPaths {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Git\cmd",
        "$env:LOCALAPPDATA\Programs\Git\bin",
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin",
        "$env:LOCALAPPDATA\Programs\Python\Python312",
        "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts"
    )

    foreach ($path in $paths) {
        if ((Test-Path $path) -and ($env:Path -notlike "*$path*")) {
            $env:Path = "$path;$env:Path"
        }
    }
}

function Install-WingetPackage {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    if ($NoInstall) {
        throw "$DisplayName is missing and -NoInstall was supplied."
    }

    if (!(Test-Command "winget")) {
        throw "$DisplayName is missing and winget is not available. Install App Installer from Microsoft Store or run on a supported Windows version."
    }

    $wingetArgs = @(
        "install",
        "--id",
        $PackageId,
        "--exact",
        "--scope",
        "user",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )
    & winget @wingetArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$DisplayName install failed or was cancelled. winget exit code: $exitCode"
    }
    Add-CommonToolPaths
}

function Ensure-Command {
    param(
        [string]$Command,
        [string]$PackageId,
        [string]$DisplayName
    )

    if (Test-Command $Command) {
        return
    }

    Install-WingetPackage -PackageId $PackageId -DisplayName $DisplayName

    if (!(Test-Command $Command)) {
        throw "$DisplayName was installed, but '$Command' is still not available on PATH. Restart PowerShell and rerun this script."
    }
}

function Resolve-InstallRoot {
    if (![string]::IsNullOrWhiteSpace($InstallRoot)) {
        return $InstallRoot
    }

    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME "AppData\Local"
    }
    return Join-Path $base "SeymourFleet\source"
}

Add-CommonToolPaths

Ensure-Command -Command "git" -PackageId "Git.Git" -DisplayName "Git for Windows"
if (!(Test-UsablePython)) {
    Install-WingetPackage -PackageId "Python.Python.3.12" -DisplayName "Python 3.12"
}
if (!(Test-UsablePython)) {
    throw "Python 3.12 was installed, but no usable Python command is available. Restart PowerShell and rerun this script."
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = Resolve-InstallRoot
}

if ((Test-Path (Join-Path $RepoPath ".git")) -and !$SkipRepoUpdate) {
    git -C $RepoPath fetch origin $Branch
    git -C $RepoPath checkout $Branch
    git -C $RepoPath pull --ff-only origin $Branch
}
elseif (Test-Path (Join-Path $RepoPath ".git")) {
    Write-Host "Using existing Seymour Fleet checkout at $RepoPath"
}
else {
    $parent = Split-Path -Parent $RepoPath
    if (!(Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    git clone --branch $Branch $RepoUrl $RepoPath
}

$LocalTest = Join-Path $RepoPath "scripts\windows-local-test.ps1"
if (!(Test-Path $LocalTest)) {
    throw "Seymour Fleet local test script not found at $LocalTest"
}

$Args = @(
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $LocalTest,
    "-TargetHost",
    $TargetHost
)

if (![string]::IsNullOrWhiteSpace($StateDir)) {
    $Args += @("-StateDir", $StateDir)
}

if ($WriteState) {
    $Args += "-WriteState"
}

powershell @Args
$localTestExitCode = $LASTEXITCODE
if ($localTestExitCode -ne 0) {
    throw "Seymour Fleet Windows local test failed. Exit code: $localTestExitCode"
}

$Result = @{
    status = "ok"
    repo_path = $RepoPath
    target_host = $TargetHost
    write_state = [bool]$WriteState
}

$Result | ConvertTo-Json -Depth 4
