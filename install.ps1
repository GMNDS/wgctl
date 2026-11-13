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
        Write-Host "Error: could not determine the latest version for $repo." -ForegroundColor Red
        Write-Host "Set it explicitly, e.g.: `$env:VERSION=\"v0.6.3\"; irm ... | iex"
        exit 1
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
} catch {
    Write-Host "Download failed. Please check your internet connection or tag: $version" -ForegroundColor Red
    if (Test-Path $tempFile) { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
    exit 1
}

# 5. Verify the downloaded binary against the published SHA-256 checksum
if ($env:WGCTL_SKIP_CHECKSUM -eq "1") {
    Write-Host "Warning: skipping checksum verification (WGCTL_SKIP_CHECKSUM=1)." -ForegroundColor Yellow
} else {
    $checksumsUrl = "https://github.com/$repo/releases/download/$version/checksums.txt"
    $checksumsText = $null
    try {
        $checksumsText = Invoke-RestMethod -Uri $checksumsUrl -Headers @{ "User-Agent" = "wgctl-installer" }
    } catch {
        Write-Host "Error: could not download checksums from $checksumsUrl" -ForegroundColor Red
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $expectedHash = ($checksumsText -split "`n" |
        Where-Object { $_ -match "\s$([regex]::Escape($assetName))\s*$" } |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Select-Object -First 1)

    if (-not $expectedHash) {
        Write-Host "Error: no checksum entry found for $assetName" -ForegroundColor Red
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    $actualHash = (Get-FileHash -Algorithm SHA256 -Path $tempFile).Hash.ToLower()
    if ($actualHash -ne $expectedHash.Trim().ToLower()) {
        Write-Host "Checksum mismatch for $assetName!" -ForegroundColor Red
        Write-Host "  expected: $expectedHash"
        Write-Host "  actual:   $actualHash"
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Host "[OK] Checksum verified (SHA-256)." -ForegroundColor Green
}

Move-Item -Path $tempFile -Destination $destPath -Force

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
