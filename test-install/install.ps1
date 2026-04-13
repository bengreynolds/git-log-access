# Git Monitor Binary Installation Script (PowerShell)
# This script installs the pre-compiled binary (no compilation required)

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\GitMonitor",
    [string]$ConfigDir = "$env:APPDATA\git-monitor",
    [switch]$Force = $false,
    [switch]$NoService = $false
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
            Write-Success "Added to PATH (restart terminal to take effect)"
        } else {
            Write-Info "Already in PATH"
        }
        
        return $true
    } catch {
        Write-ErrorMsg "Failed to install executable: $($_.Exception.Message)"
        return $false
    }
}

function New-Config {
    Write-Info "Creating user configuration..."
    
    try {
        # Create config directory
        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        
        # Get hostname for device nickname
        $hostname = $env:COMPUTERNAME
        if (!$hostname) { $hostname = "unknown" }
        
        $logDir = "$env:USERPROFILE\.local\share\git-monitor"
        
        # Create log directory
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        
        # Create user config (use default as template if available)
        $configPath = "$ConfigDir\config.json"
        
        if ((Test-Path "git-monitor.json") -and !(Test-Path $configPath)) {
            # Use provided default config as base
            $defaultConfig = Get-Content "git-monitor.json" | ConvertFrom-Json
            $defaultConfig.logPath = "$logDir\${hostname}_githistory.log"
            $defaultConfig.deviceNickname = $hostname
            
            $configJson = $defaultConfig | ConvertTo-Json -Depth 10
        } else {
            # Create minimal config
            $config = @{
                logPath = "$logDir\${hostname}_githistory.log"
                deviceNickname = $hostname
                enabledShells = @("powershell", "cmd")
                monitorScope = "user"
                logRotation = @{
                    enabled = $true
                    maxSizeMb = 100
                    keepFiles = 10
                }
                performance = @{
                    maxMemoryMb = 10
                    logBufferSize = 1000
                    flushIntervalSeconds = 30
                }
            }
            $configJson = $config | ConvertTo-Json -Depth 10
        }
        
        Set-Content -Path $configPath -Value $configJson -Encoding UTF8
        
        Write-Success "Created configuration at $configPath"
        Write-Info "Log will be written to: $logDir\${hostname}_githistory.log"
        
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
        Write-Info "Installing as Windows service..."
        try {
            $exePath = "$InstallDir\git-monitor.exe"
            $result = & $exePath install 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Service installation completed"
                Write-Info "You can now use: git-monitor start/stop"
            } else {
                Write-Warning "Service installation failed"
                Write-Info "You can still use: git-monitor run"
            }
        } catch {
            Write-Warning "Service installation failed: $($_.Exception.Message)"
            Write-Info "You can still run manually: git-monitor run"
        }
    } else {
        Write-Warning "Not running as Administrator - skipping service installation"
        Write-Info "To install as a service later, run as Administrator: git-monitor install"
    }
    
    return $true
}

function Show-CompletionMessage {
    Write-Host ""
    Write-Host "=== Git Monitor Installation Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Git Monitor has been successfully installed!" -ForegroundColor White
    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor $Colors.Blue
    Write-Host "  1. Restart your terminal (to refresh PATH)"
    Write-Host "  2. Test: git-monitor run --verbose"
    Write-Host "  3. Run some git commands in another terminal"
    Write-Host "  4. Check your log file for entries"
    Write-Host "  5. When ready: git-monitor start (if service installed)"
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor $Colors.Blue
    Write-Host "  git-monitor run --verbose    # Test in foreground"
    Write-Host "  git-monitor status           # Check service status"
    Write-Host "  git-monitor start/stop       # Control service"
    Write-Host "  git-monitor --help           # Full command list"
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor $Colors.Blue
    Write-Host "  Edit: $ConfigDir\config.json"
    Write-Host ""
    Write-Host "Getting Help:" -ForegroundColor $Colors.Blue
    Write-Host "  https://github.com/Cerebellum-Lab/git-log-access"
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
function Main {
    Write-Host "Git Monitor Binary Installer" -ForegroundColor $Colors.Blue
    Write-Host "=============================" -ForegroundColor $Colors.Blue
    Write-Host ""
    
    if (!(Test-Prerequisites)) {
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
        Write-Host "  .\install.ps1              # Install Git Monitor"
        Write-Host "  .\install.ps1 uninstall    # Uninstall Git Monitor"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  -InstallDir <path>         # Custom installation directory"
        Write-Host "  -ConfigDir <path>          # Custom config directory"
        Write-Host "  -Force                     # Overwrite existing installation"
        Write-Host "  -NoService                 # Skip Windows service installation"
        exit 1
    }
}
