# Git Monitor Binary Installation Script (PowerShell)
# This script installs the pre-compiled binary (no compilation required)

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\GitMonitor",
    [string]$ConfigDir = "$env:APPDATA\git-monitor",
    [switch]$Force = $false,
    [switch]$NoService = $false,
    [switch]$Silent = $false
)

# Colors for output
$Colors = @{
    Red = 'Red'
    Green = 'Green' 
    Yellow = 'Yellow'
    Blue = 'Cyan'
    White = 'White'
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

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check for git
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
    
    # Check that we have the executable
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
        # Create install directory
        if ($Force -and (Test-Path $InstallDir)) {
            Write-Warning "Removing existing installation..."
            Remove-Item -Path $InstallDir -Recurse -Force
        }
        
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        
        # Copy executable
        Copy-Item "git-monitor.exe" "$InstallDir\git-monitor.exe" -Force
        Write-Success "Installed executable to $InstallDir\git-monitor.exe"
        
        # Copy default config if provided
        if (Test-Path "git-monitor.json") {
            Copy-Item "git-monitor.json" "$InstallDir\default-config.json" -Force
            Write-Info "Copied default configuration"
        }
        
        # Add to PATH if not already there
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$InstallDir*") {
            Write-Info "Adding $InstallDir to user PATH..."
            if ($currentPath.EndsWith(';')) { 
                $newPath = "$currentPath$InstallDir"
            } else { 
                $newPath = "$currentPath;$InstallDir" 
            }
            $newPath = $newPath.TrimEnd(';')
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            
            # Broadcast environment change to Windows immediately
            Write-Info "Broadcasting environment changes to Windows..."
            try {
                Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class Win32 { [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult); }'
                $HWND_BROADCAST = [IntPtr]0xffff
                $WM_SETTINGCHANGE = 0x001a
                $result = [UIntPtr]::Zero
                [Win32]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
                Write-Success "Environment changes broadcast to Windows"
            } catch {
                Write-Warning "Could not broadcast environment changes: $($_.Exception.Message)"
            }
            
            # Also update current session
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
    # Use defaults for silent installation
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
    
    # Device nickname
    $defaultNickname = $env:COMPUTERNAME
    if (!$defaultNickname) { $defaultNickname = "my-computer" }
    
    Write-Host "Device Nickname:" -ForegroundColor $Colors.Blue
    Write-Host "  This identifies your device in log entries" -ForegroundColor Gray
    $deviceNickname = Read-Host "Device nickname [$defaultNickname]"
    if ([string]::IsNullOrWhiteSpace($deviceNickname)) {
        $deviceNickname = $defaultNickname
    }
    
    # Log directory
    $defaultLogDir = "$env:USERPROFILE\.local\share\git-monitor"
    Write-Host ""
    Write-Host "Log Directory:" -ForegroundColor $Colors.Blue
    Write-Host "  Where git command logs will be stored" -ForegroundColor Gray
    $logDir = Read-Host "Log directory [$defaultLogDir]"
    if ([string]::IsNullOrWhiteSpace($logDir)) {
        $logDir = $defaultLogDir
    }
    
    # Resolve environment variables and relative paths
    $logDir = [System.Environment]::ExpandEnvironmentVariables($logDir)
    if (![System.IO.Path]::IsPathRooted($logDir)) {
        $logDir = Join-Path $PWD.Path $logDir
    }
    
    # Log rotation settings
    Write-Host ""
    Write-Host "Log Rotation:" -ForegroundColor $Colors.Blue
    Write-Host "  Automatically rotate logs when they get too large" -ForegroundColor Gray
    $maxSizeMb = Read-Host "Maximum log file size in MB [100]"
    if ([string]::IsNullOrWhiteSpace($maxSizeMb) -or ![int]::TryParse($maxSizeMb, [ref]$null)) {
        $maxSizeMb = 100
    } else {
        $maxSizeMb = [int]$maxSizeMb
    }
    
    # Confirmation
    Write-Host ""
    Write-Host "=== Configuration Summary ===" -ForegroundColor $Colors.Green
    Write-Host "Device Nickname: $deviceNickname" -ForegroundColor White
    Write-Host "Log Directory: $logDir" -ForegroundColor White
    Write-Host "Log File: $logDir\${deviceNickname}_githistory.log" -ForegroundColor White
    Write-Host "Max Log Size: ${maxSizeMb}MB" -ForegroundColor White
    Write-Host ""
    
    $confirm = Read-Host "Continue with this configuration? [Y/n]"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
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
        # Get user preferences
        $config = Get-UserConfiguration
        if (!$config) {
            return $false
        }
        
        # Create config directory
        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        
        # Create log directory
        New-Item -Path $config.LogDir -ItemType Directory -Force | Out-Null
        
        # Create user config
        $configPath = "$ConfigDir\config.json"
        $logFile = "$($config.LogDir)\$($config.DeviceNickname)_githistory.log"
        
        $userConfig = @{
            logPath = $logFile
            deviceNickname = $config.DeviceNickname
            enabledShells = @("powershell", "cmd")
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
        Set-Content -Path $configPath -Value $configJson -Encoding UTF8
        
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
        # Test executable
        $exePath = "$InstallDir\git-monitor.exe"
        if (Test-Path $exePath) {
            # Test basic functionality
            $result = & $exePath --help 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Executable test passed"
                return $true
            } else {
                Write-ErrorMsg "Executable failed to run"
                return $false
            }
        } else {
            Write-ErrorMsg "git-monitor.exe not found at $exePath"
            return $false
        }
    } catch {
        Write-ErrorMsg "Installation test failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-Service {
    if ($NoService) {
        Write-Info "Skipping service installation (--NoService specified)"
        return $true
    }
    
    # Check if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Info "Installing Git Monitor as Windows service..."
        try {
            $exePath = "$InstallDir\git-monitor.exe"
            
            # Install the service
            $result = & $exePath install 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Service installed successfully"
                
                # Start the service immediately
                Write-Info "Starting Git Monitor service..."
                $startResult = & $exePath start 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Git Monitor service started successfully"
                    Write-Success "✅ Git Monitor is now running and will auto-start on boot"
                } else {
                    Write-Warning "Service installed but failed to start: $startResult"
                    Write-Info "You can start it manually with: git-monitor start"
                }
            } else {
                Write-Warning "Service installation failed: $result"
                Write-Info "You can still use manual mode: git-monitor run"
            }
        } catch {
            Write-Warning "Service installation failed: $($_.Exception.Message)"
            Write-Info "You can still run manually: git-monitor run"
        }
    } else {
        Write-Warning "Not running as Administrator - skipping service installation"
        Write-Warning "For automatic startup, run installer as Administrator"
        Write-Info "Current mode: Manual execution only (git-monitor run)"
    }
    
    return $true
}

function Show-CompletionMessage {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    Write-Host ""
    Write-Host "=== Git Monitor Installation Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "🎉 Git Monitor has been successfully installed!" -ForegroundColor White
    Write-Host ""
    
    if ($isAdmin -and !$NoService) {
        Write-Host "✅ AUTOMATIC STARTUP ENABLED" -ForegroundColor Green
        Write-Host "   • Git Monitor service is running" -ForegroundColor White
        Write-Host "   • Will automatically start on computer boot" -ForegroundColor White
        Write-Host "   • No manual startup required!" -ForegroundColor White
        Write-Host ""
        
        Write-Host "🔄 IMPORTANT: Restart your computer" -ForegroundColor Yellow
        Write-Host "   • Ensures PATH is fully refreshed" -ForegroundColor White
        Write-Host "   • Verifies service auto-starts correctly" -ForegroundColor White
        Write-Host "   • After restart: git-monitor commands work everywhere" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Commands after restart:" -ForegroundColor $Colors.Blue
        Write-Host "  git-monitor status           # Check if service is running"
        Write-Host "  git-monitor --help           # Full command list"
        Write-Host "  git-monitor run --verbose    # Test in foreground (optional)"
    } else {
        Write-Host "⚠️  MANUAL MODE ONLY" -ForegroundColor Yellow
        if (!$isAdmin) {
            Write-Host "   • Installer was not run as Administrator" -ForegroundColor White
            Write-Host "   • Service auto-start not available" -ForegroundColor White
        }
        Write-Host "   • Use: git-monitor run --verbose to start monitoring" -ForegroundColor White
        Write-Host ""
        
        Write-Host "🔄 Please restart your computer" -ForegroundColor Yellow
        Write-Host "   • Ensures PATH works in all terminals" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Commands after restart:" -ForegroundColor $Colors.Blue
        Write-Host "  git-monitor run --verbose    # Start monitoring (required each time)"
        Write-Host "  git-monitor --help           # Full command list"
    }
    
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor $Colors.Blue
    Write-Host "  Location: $ConfigDir\config.json"
    Write-Host "  Device: $(try { (Get-Content "$ConfigDir\config.json" | ConvertFrom-Json).deviceNickname } catch { 'Configuration' })"
    Write-Host ""
    Write-Host "Getting Help:" -ForegroundColor $Colors.Blue
    Write-Host "  https://github.com/bengreynolds/git-log-access"
    Write-Host ""
}

function Uninstall {
    Write-Info "Uninstalling Git Monitor..."
    
    try {
        # Stop and remove service if it exists
        $exePath = "$InstallDir\git-monitor.exe"
        if (Test-Path $exePath) {
            & $exePath stop 2>$null
            & $exePath uninstall 2>$null
        }
        
        # Remove from PATH
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -like "*$InstallDir*") {
            $newPath = $currentPath.Split(';') | Where-Object { $_ -ne $InstallDir } | Join-Object ';'
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Success "Removed from PATH"
        }
        
        # Remove installation directory
        if (Test-Path $InstallDir) {
            Remove-Item -Path $InstallDir -Recurse -Force
            Write-Success "Removed installation directory"
        }
        
        # Option to remove config and logs
        Write-Host ""
        $removeData = Read-Host "Remove configuration and log files? [y/N]"
        if ($removeData -eq 'y' -or $removeData -eq 'Y') {
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

# Main execution
function Test-ExistingInstallation {
    # Check if Git Monitor is already installed
    $exePath = "$InstallDir\git-monitor.exe"
    $configPath = "$ConfigDir\config.json"
    $commandAvailable = $false
    
    # Check if git-monitor command is available
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
                # Set Force to true for the rest of the installation
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
    
    # Check for existing installation and prompt for reinstall
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
    
    Install-Service
    Show-CompletionMessage
}

# Handle command line
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
        Write-Host "  .\.install.ps1              # Install Git Monitor (prompts for reinstall if exists)"
        Write-Host "  .\.install.ps1 uninstall    # Uninstall Git Monitor"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -InstallDir <path>         # Custom installation directory"
        Write-Host "  -ConfigDir <path>          # Custom config directory"
        Write-Host "  -Force                     # Overwrite existing installation without prompting"
        Write-Host "  -NoService                 # Skip Windows service installation"
        Write-Host "  -Silent                    # Use defaults, no interactive prompts (skips reinstall)"
        exit 1
    }
}