# Git Monitor Binary Installation Script (PowerShell)
# This script installs the pre-compiled binary (no compilation required)

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\GitMonitor",
    [string]$ConfigDir = "$env:APPDATA\git-monitor",
    [switch]$Force = $false,
    [switch]$NoService = $false,
    [switch]$Silent = $false
)

$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Cyan"
    White = "White"
}

function Write-Info($Message) {
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Blue
}

function Write-Success($Message) {
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Green
}

function Write-Warning($Message) {
    Write-Host "[WARN] $Message" -ForegroundColor $Colors.Yellow
}

function Write-ErrorMsg($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
}

function Get-ExePath {
    return Join-Path $InstallDir "git-monitor.exe"
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."

    try {
        $null = git --version
        Write-Success "Git found"
    } catch {
        Write-ErrorMsg "Git not found"
        Write-Host "Please install Git:" -ForegroundColor Yellow
        Write-Host "  winget install Git.Git" -ForegroundColor Yellow
        Write-Host "  Or download from https://git-scm.com/download/win" -ForegroundColor Yellow
        return $false
    }

    if (!(Test-Path "git-monitor.exe")) {
        Write-ErrorMsg "git-monitor.exe not found in current directory"
        Write-Host "Please ensure you've extracted the binary distribution correctly" -ForegroundColor Yellow
        return $false
    }

    Write-Success "Prerequisites check passed"
    return $true
}

function Install-Executable {
    Write-Info "Installing Git Monitor executable..."

    try {
        if ($Force -and (Test-Path $InstallDir)) {
            Write-Warning "Removing existing installation..."
            Remove-Item -Path $InstallDir -Recurse -Force
        }

        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        Copy-Item "git-monitor.exe" (Get-ExePath) -Force
        Write-Success "Installed executable to $(Get-ExePath)"

        if (Test-Path "git-monitor.json") {
            Copy-Item "git-monitor.json" (Join-Path $InstallDir "default-config.json") -Force
            Write-Info "Copied default configuration"
        }

        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$InstallDir*") {
            Write-Info "Adding $InstallDir to user PATH..."
            if ([string]::IsNullOrWhiteSpace($currentPath)) {
                $newPath = $InstallDir
            } elseif ($currentPath.EndsWith(';')) {
                $newPath = "$currentPath$InstallDir"
            } else {
                $newPath = "$currentPath;$InstallDir"
            }
            $newPath = $newPath.TrimEnd(';')
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

            try {
                Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Win32 { [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult); }'
                $HWND_BROADCAST = [IntPtr]0xffff
                $WM_SETTINGCHANGE = 0x001a
                $result = [UIntPtr]::Zero
                [Win32]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
            } catch {
                Write-Warning "Could not broadcast environment changes: $($_.Exception.Message)"
            }

            $env:PATH += ";$InstallDir"
            Write-Success "Added to PATH and refreshed current session"
        } else {
            Write-Info "Already in PATH"
        }

        return $true
    } catch {
        Write-ErrorMsg "Failed to install executable: $($_.Exception.Message)"
        return $false
    }
}

function Get-UserConfiguration {
    if ($Silent) {
        $defaultNickname = $env:COMPUTERNAME
        if (!$defaultNickname) { $defaultNickname = "my-computer" }

        return @{
            DeviceNickname = $defaultNickname
            LogDir = "$env:USERPROFILE\.local\share\git-monitor"
            MaxSizeMb = 100
        }
    }

    Write-Host ""
    Write-Host "=== Git Monitor Configuration ===" -ForegroundColor $Colors.Blue
    Write-Host "Please provide your preferences for Git Monitor setup" -ForegroundColor White
    Write-Host ""

    $defaultNickname = $env:COMPUTERNAME
    if (!$defaultNickname) { $defaultNickname = "my-computer" }

    Write-Host "Device Nickname:" -ForegroundColor $Colors.Blue
    Write-Host "  This identifies your device in log entries" -ForegroundColor Gray
    $deviceNickname = Read-Host "Device nickname [$defaultNickname]"
    if ([string]::IsNullOrWhiteSpace($deviceNickname)) {
        $deviceNickname = $defaultNickname
    }

    $defaultLogDir = "$env:USERPROFILE\.local\share\git-monitor"
    Write-Host ""
    Write-Host "Log Directory:" -ForegroundColor $Colors.Blue
    Write-Host "  Where git command logs will be stored" -ForegroundColor Gray
    $logDir = Read-Host "Log directory [$defaultLogDir]"
    if ([string]::IsNullOrWhiteSpace($logDir)) {
        $logDir = $defaultLogDir
    }

    $logDir = [System.Environment]::ExpandEnvironmentVariables($logDir)
    if (![System.IO.Path]::IsPathRooted($logDir)) {
        $logDir = Join-Path $PWD.Path $logDir
    }

    Write-Host ""
    Write-Host "Log Rotation:" -ForegroundColor $Colors.Blue
    Write-Host "  Automatically rotate logs when they get too large" -ForegroundColor Gray
    $maxSizeMb = Read-Host "Maximum log file size in MB [100]"
    if ([string]::IsNullOrWhiteSpace($maxSizeMb) -or !($maxSizeMb -match '^\d+$')) {
        $maxSizeMb = 100
    } else {
        $maxSizeMb = [int]$maxSizeMb
    }

    Write-Host ""
    Write-Host "=== Configuration Summary ===" -ForegroundColor $Colors.Green
    Write-Host "Device Nickname: $deviceNickname" -ForegroundColor White
    Write-Host "Log Directory: $logDir" -ForegroundColor White
    Write-Host "Log File: $logDir\${deviceNickname}_githistory.log" -ForegroundColor White
    Write-Host "Max Log Size: ${maxSizeMb}MB" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Continue with this configuration? [Y/n]"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Write-Warning "Configuration cancelled by user"
        return $null
    }

    return @{
        DeviceNickname = $deviceNickname
        LogDir = $logDir
        MaxSizeMb = $maxSizeMb
    }
}

function New-Config {
    Write-Info "Setting up configuration..."

    try {
        $config = Get-UserConfiguration
        if (!$config) {
            return $false
        }

        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        New-Item -Path $config.LogDir -ItemType Directory -Force | Out-Null

        $configPath = Join-Path $ConfigDir "config.json"
        $logFile = Join-Path $config.LogDir "$($config.DeviceNickname)_githistory.log"

        $userConfig = @{
            logPath = $logFile
            deviceNickname = $config.DeviceNickname
            enabledShells = @("powershell", "pwsh")
            monitorScope = "user"
            logRotation = @{
                enabled = $true
                maxSizeMb = $config.MaxSizeMb
                keepFiles = 10
            }
            performance = @{
                maxMemoryMb = 10
                logBufferSize = 1000
                flushIntervalSeconds = 30
            }
        }

        $configJson = $userConfig | ConvertTo-Json -Depth 10
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, $configJson, $utf8NoBom)

        Write-Success "Created configuration at $configPath"
        Write-Success "Log will be written to: $logFile"
        return $true
    } catch {
        Write-ErrorMsg "Failed to create configuration: $($_.Exception.Message)"
        return $false
    }
}

function Test-Installation {
    Write-Info "Testing installation..."

    try {
        $exePath = Get-ExePath
        if (!(Test-Path $exePath)) {
            Write-ErrorMsg "git-monitor.exe not found at $exePath"
            return $false
        }

        $null = & $exePath --help 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Executable test passed"
            return $true
        }

        Write-ErrorMsg "Executable failed to run"
        return $false
    } catch {
        Write-ErrorMsg "Installation test failed: $($_.Exception.Message)"
        return $false
    }
}

function Enable-Monitoring {
    if ($NoService) {
        Write-Info "Skipping automatic monitor activation (--NoService specified)"
        Write-Info "You can enable hooks and the background monitor later with: git-monitor start"
        return $true
    }

    Write-Info "Enabling shell hooks and background monitor..."

    try {
        $exePath = Get-ExePath
        $process = Start-Process -FilePath $exePath -ArgumentList "start" -NoNewWindow -PassThru
        if ($process.WaitForExit(5000)) {
            if ($process.ExitCode -eq 0) {
                Write-Success "Monitoring enabled"
                Write-Info "Open a new PowerShell or pwsh window to load the installed profile hook"
            } else {
                Write-Warning "Automatic activation failed with exit code $($process.ExitCode)"
                Write-Info "You can enable it later with: git-monitor start"
            }
        } else {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Warning "Automatic activation did not complete within 5 seconds"
            Write-Info "You can enable it later with: git-monitor start"
        }
    } catch {
        Write-Warning "Automatic activation failed: $($_.Exception.Message)"
        Write-Info "You can enable it later with: git-monitor start"
    }

    return $true
}

function Show-CompletionMessage {
    Write-Host ""
    Write-Host "=== Git Monitor Installation Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Git Monitor has been successfully installed." -ForegroundColor White
    Write-Host ""

    if ($NoService) {
        Write-Host "Monitoring has not been enabled yet." -ForegroundColor Yellow
        Write-Host "Run 'git-monitor start' when you are ready to install hooks and start the daemon." -ForegroundColor White
    } else {
        Write-Host "Hook-based interception and the background monitor were enabled." -ForegroundColor Green
        Write-Host "Open a new PowerShell or pwsh session so the installed profile hook is loaded." -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor $Colors.Blue
    Write-Host "  Open a new terminal so PATH and shell profile changes are picked up"
    Write-Host "  Run git-monitor status to confirm interception and daemon state"
    Write-Host "  Run a few git commands in a repository and inspect your log file"
    Write-Host ""
    Write-Host "Useful commands:" -ForegroundColor $Colors.Blue
    Write-Host "  git-monitor start            # Enable hooks and start the background monitor"
    Write-Host "  git-monitor stop             # Disable hooks and stop the background monitor"
    Write-Host "  git-monitor status           # Show hook and daemon status"
    Write-Host "  git-monitor run --verbose    # Foreground smoke test"
    Write-Host "  git-monitor --help           # Full command list"
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor $Colors.Blue
    Write-Host "  Location: $ConfigDir\config.json"
    Write-Host "  Device: $(try { (Get-Content (Join-Path $ConfigDir 'config.json') | ConvertFrom-Json).deviceNickname } catch { 'Configuration' })"
    Write-Host ""
    Write-Host "Getting Help:" -ForegroundColor $Colors.Blue
    Write-Host "  https://github.com/bengreynolds/git-log-access"
    Write-Host ""
}

function Uninstall {
    Write-Info "Uninstalling Git Monitor..."

    try {
        $exePath = Get-ExePath
        if (Test-Path $exePath) {
            & $exePath stop 2>$null
            & $exePath uninstall 2>$null
        }

        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -like "*$InstallDir*") {
            $newPath = (($currentPath.Split(';') | Where-Object { $_ -and $_ -ne $InstallDir }) -join ';')
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Success "Removed from PATH"
        }

        if (Test-Path $InstallDir) {
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-Success "Removed installation directory"
        }

        Write-Host ""
        $removeData = Read-Host "Remove configuration and log files? [y/N]"
        if ($removeData -eq "y" -or $removeData -eq "Y") {
            if (Test-Path $ConfigDir) {
                Remove-Item -Path $ConfigDir -Recurse -Force
                Write-Success "Removed configuration"
            }
        }

        Write-Success "Uninstallation complete"
    } catch {
        Write-ErrorMsg "Uninstall failed: $($_.Exception.Message)"
    }
}

function Test-ExistingInstallation {
    $exePath = Get-ExePath
    $configPath = Join-Path $ConfigDir "config.json"
    $commandAvailable = $false

    try {
        $null = Get-Command git-monitor -ErrorAction SilentlyContinue
        $commandAvailable = $true
    } catch {}

    if ((Test-Path $exePath) -or (Test-Path $configPath) -or $commandAvailable) {
        Write-Warning "Git Monitor installation detected:"
        if (Test-Path $exePath) { Write-Host "  Executable: $exePath" -ForegroundColor Yellow }
        if (Test-Path $configPath) { Write-Host "  Config: $configPath" -ForegroundColor Yellow }
        if ($commandAvailable) { Write-Host "  Command available in PATH" -ForegroundColor Yellow }

        if ($Force) {
            Write-Info "Force flag detected - proceeding with reinstallation..."
            return $true
        }

        if ($Silent) {
            Write-Warning "Silent mode - skipping reinstall (use -Force to reinstall)"
            return $false
        }

        Write-Host ""
        do {
            $response = Read-Host "Do you want to reinstall? This will overwrite existing files. [y/N]"
            $response = $response.Trim().ToLower()

            if ($response -eq "" -or $response -eq "n" -or $response -eq "no") {
                Write-Host "Installation cancelled." -ForegroundColor Yellow
                Write-Host "Use -Force flag to reinstall without prompting" -ForegroundColor Yellow
                return $false
            } elseif ($response -eq "y" -or $response -eq "yes") {
                Write-Info "Proceeding with reinstallation..."
                $script:Force = $true
                return $true
            } else {
                Write-Host "Please enter 'y' for yes or 'n' for no." -ForegroundColor Red
            }
        } while ($true)
    }

    return $true
}

function Main {
    Write-Host "Git Monitor Binary Installer" -ForegroundColor $Colors.Blue
    Write-Host "=============================" -ForegroundColor $Colors.Blue
    Write-Host ""

    if (!(Test-Prerequisites)) {
        exit 1
    }

    if (!(Test-ExistingInstallation)) {
        exit 1
    }

    if (!(Install-Executable)) {
        exit 1
    }

    if (!(New-Config)) {
        exit 1
    }

    if (!(Test-Installation)) {
        exit 1
    }

    Enable-Monitoring | Out-Null
    Show-CompletionMessage
}

switch -Regex ($args[0]) {
    "^(uninstall|remove)$" {
        Uninstall
        break
    }
    "^(install|)$" {
        Main
        break
    }
    default {
        Write-Host "Git Monitor Binary Installer"
        Write-Host ""
        Write-Host "Usage:"
        Write-Host "  .\install.ps1              # Install Git Monitor (prompts for reinstall if exists)"
        Write-Host "  .\install.ps1 uninstall    # Uninstall Git Monitor"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -InstallDir <path>         # Custom installation directory"
        Write-Host "  -ConfigDir <path>          # Custom config directory"
        Write-Host "  -Force                     # Overwrite existing installation without prompting"
        Write-Host "  -NoService                 # Skip automatic hook and daemon activation"
        Write-Host "  -Silent                    # Use defaults, no interactive prompts (skips reinstall)"
        exit 1
    }
}
