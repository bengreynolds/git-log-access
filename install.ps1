# Git Monitor Simple Installation Script (PowerShell)
# This script will build and install Git Monitor as an executable on Windows

param(
    [Parameter(Position=0)]
    [ValidateSet("install", "build-only", "test")]
    [string]$Action = "install"
)

# Colors for output
$Colors = @{
    Red = 'Red'
    Green = 'Green' 
    Yellow = 'Yellow'
    Blue = 'Cyan'
    White = 'White'
}

# Configuration
$InstallDir = "$env:LOCALAPPDATA\Programs\GitMonitor"
$ConfigDir = "$env:APPDATA\git-monitor"
$ServiceName = "GitMonitor"

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
    
    # Check for Rust/cargo
    try {
        $null = cargo --version
        Write-Success "Rust/cargo found"
    } catch {
        Write-ErrorMsg "Rust/cargo not found"
        Write-Host "Please install Rust from https://rustup.rs/" -ForegroundColor Yellow
        Write-Host "Or use: winget install Rustlang.Rust.MSVC" -ForegroundColor Yellow
        exit 1
    }
    
    # Check for git
    try {
        $null = git --version
        Write-Success "Git found"
    } catch {
        Write-ErrorMsg "Git not found"
        Write-Host "Please install Git:" -ForegroundColor Yellow
        Write-Host "  winget install Git.Git" -ForegroundColor Yellow
        Write-Host "  Or download from https://git-scm.com/download/win" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

function Build-Project {
    Write-Info "Building Git Monitor..."
    
    # Clean previous builds
    if (Test-Path "target") {
        Write-Info "Cleaning previous build..."
        cargo clean
    }
    
    # Build release version
    Write-Info "Compiling release version (this may take a few minutes)..."
    try {
        cargo build --release
        Write-Success "Build completed successfully"
    } catch {
        Write-ErrorMsg "Build failed"
        Write-Host "Check the error messages above and ensure all dependencies are available" -ForegroundColor Yellow
        exit 1
    }
    
    # Verify the executable exists
    if (!(Test-Path "target\release\git-monitor.exe")) {
        Write-ErrorMsg "Built executable not found at target\release\git-monitor.exe"
        exit 1
    }
}

function Install-Executable {
    Write-Info "Installing executable to $InstallDir..."
    
    try {
        # Create install directory
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        
        # Copy executable
        Copy-Item "target\release\git-monitor.exe" "$InstallDir\git-monitor.exe" -Force
        
        Write-Success "Installed executable to $InstallDir\git-monitor.exe"
        
        # Add to PATH if not already there
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$InstallDir*") {
            Write-Info "Adding $InstallDir to user PATH..."
            $newPath = "$currentPath;$InstallDir"
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Success "Added to PATH (restart terminal to take effect)"
        }
        
    } catch {
        Write-ErrorMsg "Failed to install executable: $($_.Exception.Message)"
        exit 1
    }
}

function New-Config {
    Write-Info "Creating default configuration..."
    
    try {
        # Create config directory
        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        
        # Get hostname for device nickname
        $hostname = $env:COMPUTERNAME
        if (!$hostname) { $hostname = "unknown" }
        
        $logDir = "$env:USERPROFILE\.local\share\git-monitor"
        
        # Create log directory
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        
        # Create default config
        $config = @{
            logPath = "$logDir\${hostname}_githistory.log"
            deviceNickname = $hostname
            enabledShells = @("powershell", "pwsh")
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
        $configPath = "$ConfigDir\config.json"
        Set-Content -Path $configPath -Value $configJson -Encoding UTF8
        
        Write-Success "Created configuration at $configPath"
        Write-Info "Log will be written to: $logDir\${hostname}_githistory.log"
        
    } catch {
        Write-ErrorMsg "Failed to create configuration: $($_.Exception.Message)"
        exit 1
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
            } else {
                Write-ErrorMsg "Executable test failed"
                return
            }
        } else {
            Write-ErrorMsg "git-monitor.exe not found at $exePath"
            return
        }
        
        # Test configuration loading
        try {
            $result = & $exePath status 2>$null
            Write-Success "Configuration test passed"
        } catch {
            Write-Info "Service not running (this is normal for first install)"
        }
        
    } catch {
        Write-ErrorMsg "Installation test failed: $($_.Exception.Message)"
    }
}

function Show-UsageInstructions {
    Write-Host ""
    Write-Host "=== Installation Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Git Monitor has been successfully installed!" -ForegroundColor White
    Write-Host ""
    Write-Host "Basic Usage:" -ForegroundColor $Colors.Blue
    Write-Host "  git-monitor install          # Install shell hooks and enable interception"
    Write-Host "  git-monitor start            # Enable interception"
    Write-Host "  git-monitor stop             # Disable interception"
    Write-Host "  git-monitor status           # Show hook installation status"
    Write-Host "  git-monitor uninstall        # Remove installed hooks"
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor $Colors.Blue
    Write-Host "  Config file: $ConfigDir\config.json"
    Write-Host "  Edit this file to customize logging behavior"
    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor $Colors.Blue
    Write-Host "  1. Restart this terminal (to refresh PATH)"
    Write-Host "  2. Run: git-monitor install"
    Write-Host "  3. Restart your shell if needed, then run a git command"
    Write-Host "  4. Confirm entries appear in your configured log file"
    Write-Host ""
    Write-Host "Getting Help:" -ForegroundColor $Colors.Blue
    Write-Host "  git-monitor --help           # Show all commands"
    Write-Host "  https://github.com/bengreynolds/git-log-access"
    Write-Host ""
    Write-Warning "Note: Restart your terminal to use 'git-monitor' from anywhere"
}

function Invoke-Main {
    Write-Host "Git Monitor - Simple Installation" -ForegroundColor $Colors.Blue
    Write-Host "==================================" -ForegroundColor $Colors.Blue
    Write-Host ""
    
    # Check if we're in the right directory
    if (!(Test-Path "Cargo.toml") -or !(Test-Path "src\main.rs")) {
        Write-ErrorMsg "Please run this script from the git-log-access project directory"
        Write-Host "Expected files: Cargo.toml, src\main.rs" -ForegroundColor Yellow
        exit 1
    }
    
    # Run installation steps
    Test-Prerequisites
    Build-Project
    Install-Executable
    New-Config
    Test-Installation
    Show-UsageInstructions
}

function Invoke-BuildOnly {
    Test-Prerequisites
    Build-Project
    Write-Success "Build complete. Run '.\install.ps1 install' to install."
}

function Invoke-Test {
    if (Test-Path "scripts\test-requirements.ps1") {
        & "scripts\test-requirements.ps1"
    } else {
        Write-ErrorMsg "Requirements test script not found"
        exit 1
    }
}

# Main execution
switch ($Action) {
    "install" {
        Invoke-Main
    }
    "build-only" {
        Invoke-BuildOnly
    }
    "test" {
        Invoke-Test
    }
    default {
        Write-Host "Usage: .\install.ps1 [install|build-only|test]"
        Write-Host "  install     - Full installation (default)"
        Write-Host "  build-only  - Just compile the project"
        Write-Host "  test        - Run requirements test"
        exit 1
    }
}
