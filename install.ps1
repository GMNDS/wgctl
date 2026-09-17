# wgctl Windows installer script
# Usage:
#   irm https://raw.githubusercontent.com/gmnds/wgctl/main/install.ps1 | iex
#
# Custom version:
#   $env:VERSION="v0.5.1"; irm https://raw.githubusercontent.com/gmnds/wgctl/main/install.ps1 | iex

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repo = if ($env:REPO) { $env:REPO } else { "gmnds/wgctl" }
$binaryName = "wgctl.exe"
$installDir = if ($env:BIN_DIR) { $env:BIN_DIR } else { "$env:LOCALAPPDATA\Programs\wgctl" }

Write-Host @"
    ██╗    ██╗ ██████╗  ██████╗████████╗██╗     
    ██║    ██║██╔════╝ ██╔════╝╚══██╔══╝██║     
    ██║ █╗ ██║██║  ███╗██║        ██║   ██║     
    ██║███╗██║██║   ██║██║        ██║   ██║     
    ╚███╔███╔╝╚██████╔╝╚██████╗   ██║   ███████╗
     ╚══╝╚══╝  ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝
"@ -ForegroundColor Cyan

Write-Host "Friendly WireGuard Management CLI Installer (Windows)`n" -ForegroundColor White

# 1. Check architecture
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
if ($arch -ne [System.Runtime.InteropServices.Architecture]::X64) {
    Write-Warning "Detected architecture '$arch'. Currently, prebuilt Windows binaries are targeted for x64."
}

# 2. Resolve version
$version = $env:VERSION
if (-not $version -or $version -eq "latest") {
    Write-Host "Finding latest release for $repo..." -ForegroundColor Gray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $latest = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "wgctl-installer" }
        $version = $latest.tag_name
    } catch {
        $version = "v0.5.1"
    }
}

$assetName = "wgctl-windows-amd64.exe"
$downloadUrl = "https://github.com/$repo/releases/download/$version/$assetName"
$destPath = Join-Path $installDir $binaryName

Write-Host "Target version:  $version" -ForegroundColor Green
Write-Host "Install folder:  $installDir" -ForegroundColor Green
Write-Host "Downloading:     $downloadUrl`n" -ForegroundColor Gray

# 3. Create destination directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 4. Download executable
$tempFile = [System.IO.Path]::GetTempFileName()
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -UseBasicParsing
    Move-Item -Path $tempFile -Destination $destPath -Force
} catch {
    Write-Error "Download failed. Please check your internet connection or tag: $version"
    exit 1
} finally {
    if (Test-Path $tempFile) {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# 5. Add to User PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
$pathEntries = $userPath -split ';' | Where-Object { $_ -ne "" }

if ($pathEntries -notcontains $installDir) {
    Write-Host "Adding $installDir to User PATH..." -ForegroundColor Yellow
    $newPath = ($pathEntries + $installDir) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
    
    # Also update current PowerShell session PATH
    $env:Path = "$env:Path;$installDir"
}

Write-Host "`n[OK] wgctl successfully installed to $destPath!" -ForegroundColor Green

# 6. Verify version
try {
    & $destPath --version
} catch {
    # Ignore if execution policy restricts invocation
}

Write-Host "`nNext steps:" -ForegroundColor White
Write-Host "  - Connect to a remote server:  wgctl remote connect https://vpn.example.com:7443 --token <token>" -ForegroundColor Gray
Write-Host "  - Check remote status:         wgctl remote status" -ForegroundColor Gray
Write-Host "  - Open interactive menu:       wgctl menu" -ForegroundColor Gray
Write-Host "`nNote: If the 'wgctl' command is not recognized in other open terminal windows, restart them to refresh the PATH.`n" -ForegroundColor DarkGray
