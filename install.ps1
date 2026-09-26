# install.ps1 (Windows PowerShell Automated Installer for Coursera DL)
# Repository: https://github.com/courseradl/coursera-dl-gui

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$GithubRepo = "courseradl/coursera-dl-gui"
$ReleasesApi = "https://api.github.com/repos/$GithubRepo/releases/latest"

# --- Constants & Colors ---
$C_Success = "Green"
$C_Info = "Yellow"
$C_Error = "Red"
$C_Cyan = "Cyan"
$C_Primary = "Blue"

function Show-Header {
    Write-Host "`n"
    Write-Host "  ____                                       ____  _     " -ForegroundColor $C_Cyan
    Write-Host " / ___|___  _   _ _ __ ___  ___ _ __ __ _   |  _ \| |    " -ForegroundColor $C_Cyan
    Write-Host "| |   / _ \| | | | '__/ __|/ _ \ '__/ _` |  | | | | |    " -ForegroundColor $C_Cyan
    Write-Host "| |__| (_) | |_| | |  \__ \  __/ | | (_| |  | |_| | |___ " -ForegroundColor $C_Cyan
    Write-Host " \____\___/ \__,_|_|  |___/\___|_|  \__,_|  |____/|_____|" -ForegroundColor $C_Cyan
    Write-Host "                                                         " -ForegroundColor $C_Cyan
    Write-Host "  High-performance desktop application for personal offline course backups`n" -ForegroundColor DarkGray
}

function Show-Step([string]$Message) { Write-Host "`n==> " -NoNewline -ForegroundColor $C_Primary; Write-Host $Message -ForegroundColor White }
function Show-Ok([string]$Message) { Write-Host "   $([char]0x2714) $Message" -ForegroundColor $C_Success }
function Show-Info([string]$Message) { Write-Host "   $([char]0x279C) $Message" -ForegroundColor $C_Info }
function Quit-Error([string]$Message) { 
    Write-Host "`n   $([char]0x2716) ERROR: $Message`n" -ForegroundColor $C_Error
    Read-Host "   Press Enter to exit..."
    exit 1 
}
function Normalize-RegistryPath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return $Value.Split(",")[0].Trim('"')
}

Show-Header

# --- Phase 1: Detect Architecture ---
Show-Step "Checking system architecture"
$Arch = $env:PROCESSOR_ARCHITECTURE
if ($Arch -eq "x86" -or $Arch -match "32") {
    Quit-Error "Windows 32-bit is strictly not supported."
} elseif ($Arch -eq "AMD64" -or $Arch -eq "x64" -or $Arch -eq "ARM64") {
    $TargetArch = "x64"
} else {
    Quit-Error "Unsupported architecture: $Arch"
}
Show-Ok "Architecture detected: $TargetArch"

# --- Phase 2: Fetch Latest Release Info ---
Show-Step "Checking for latest version"
try {
    $Headers = @{
        "User-Agent" = "Coursera-DL-Installer"
        "Accept" = "application/vnd.github.v3+json"
    }
    $Release = Invoke-RestMethod -Uri $ReleasesApi -Headers $Headers -Method Get -ErrorAction Stop
    $RemoteVersion = ($Release.tag_name -replace '^v', '')
    
    # Match Windows .exe asset
    $Asset = $Release.assets | Where-Object { $_.name -like "*.exe" } | Select-Object -First 1
    if (!$Asset) {
        throw "Could not locate Windows .exe release asset."
    }
    $DownloadUrl = $Asset.browser_download_url
} catch {
    Quit-Error "Failed to reach GitHub Releases API: $_"
}
Show-Ok "Latest stable release: v$RemoteVersion"

# --- Phase 3: Check Local Installation ---
Show-Step "Verifying local installation"
$SkipDownload = $false
$AppPath = Join-Path $env:LOCALAPPDATA "Programs\coursera-dl-gui\Coursera DL.exe"

# Search Registry for existing installation
$RegKeys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($Key in $RegKeys) {
    $App = Get-ItemProperty $Key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Coursera DL*" -or $_.DisplayName -like "*coursera-dl*" } | Select-Object -First 1
    if ($App) {
        $InstallLocation = Normalize-RegistryPath $App.InstallLocation
        if ($InstallLocation -and (Test-Path (Join-Path $InstallLocation "Coursera DL.exe"))) {
            $AppPath = Join-Path $InstallLocation "Coursera DL.exe"
            break
        } elseif ($App.DisplayIcon) {
            $DisplayIconPath = Normalize-RegistryPath $App.DisplayIcon
            if (Test-Path $DisplayIconPath) {
                $AppPath = $DisplayIconPath
                break
            }
        }
    }
}

if (Test-Path $AppPath) {
    try {
        $LocalVersion = (Get-Item $AppPath).VersionInfo.FileVersion
        if ($LocalVersion -eq $RemoteVersion) {
            Show-Ok "Coursera DL is already up-to-date (v$RemoteVersion)"
            $SkipDownload = $true
        } else {
            Show-Info "An update is available (v$LocalVersion -> v$RemoteVersion)"
        }
    } catch {
        Show-Info "Coursera DL detected. Updating to latest release."
    }
} else {
    Show-Info "Coursera DL is not installed yet"
}

# --- Phase 4: Download and Run Installer ---
if (-not $SkipDownload) {
    $ExePath = Join-Path $env:TEMP "Coursera_DL_Installer.exe"
    Show-Step "Downloading Coursera DL"
    Show-Info "Downloading official Windows installer..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath
    Unblock-File -Path $ExePath -ErrorAction SilentlyContinue
    Show-Ok "Download completed"

    Show-Step "Installing application"
    Show-Info "Running Setup..."
    try {
        Start-Process -FilePath $ExePath -ArgumentList "/S" -Verb RunAs -Wait
        Show-Ok "Coursera DL installed successfully"
    } catch {
        if ($_.Exception.Message -match "virus" -or $_.Exception.HResult -eq -2147024671) {
            Write-Host "`n   [!] WINDOWS DEFENDER INTERCEPTED THE INSTALLER" -ForegroundColor $C_Error
            Write-Host "   To allow:" -ForegroundColor $C_Info
            Write-Host "   1. Open 'Windows Security'" -ForegroundColor White
            Write-Host "   2. Go to 'Virus & threat protection' -> 'Protection history'" -ForegroundColor White
            Write-Host "   3. Click 'Actions' -> 'Allow on device'" -ForegroundColor White
            Write-Host "   4. Re-run this installer script.`n" -ForegroundColor White
            exit 1
        } else {
            # Fallback to interactive execution if silent execution fails
            Start-Process -FilePath $ExePath -Wait
            Show-Ok "Setup completed"
        }
    }
    
    Remove-Item -Path $ExePath -Force -ErrorAction SilentlyContinue
}

# --- Completion ---
Write-Host "`n"
Write-Host "  ================================================================" -ForegroundColor $C_Success
Write-Host "  🎉 Coursera DL Installation Complete!" -ForegroundColor $C_Success
Write-Host "  You can launch Coursera DL from your Start Menu or Desktop." -ForegroundColor White
Write-Host "  ================================================================`n" -ForegroundColor $C_Success
