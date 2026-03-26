# Installation Requirements Test Script (PowerShell)
# Tests all dependencies and requirements for Git Monitor installation

param(
    [switch]$Verbose = $false
)

# Colors for output
$Colors = @{
    Red = 'Red'
    Green = 'Green' 
    Yellow = 'Yellow'
    White = 'White'
}

# Test counters
$Global:PassedTests = 0
$Global:FailedTests = 0
$Global:Warnings = 0

function Write-Info($Message) {
    Write-Host "[INFO] $Message" -ForegroundColor $Colors.Green
}

function Write-Warning($Message) {
    Write-Host "[WARN] $Message" -ForegroundColor $Colors.Yellow
    $Global:Warnings++
}

function Write-Error($Message) {
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
    $Global:FailedTests++
}

function Write-Pass($Message) {
    Write-Host "[PASS] $Message" -ForegroundColor $Colors.Green
    $Global:PassedTests++
}

function Test-RustToolchain {
    Write-Host "Testing Rust toolchain..." -ForegroundColor White
    
    # Test cargo
    try {
        $cargoVersion = cargo --version 2>$null
        if ($cargoVersion) {
            Write-Pass "Cargo found: $cargoVersion"
            
            # Test minimum version (1.70+)
            if ($cargoVersion -match '(\d+)\.(\d+)') {
                $major = [int]$matches[1]
                $minor = [int]$matches[2]
                if (($major -gt 1) -or ($major -eq 1 -and $minor -ge 70)) {
                    Write-Pass "Rust version is compatible (>= 1.70)"
                } else {
                    Write-Error "Rust version too old. Need 1.70 or higher, found $($major).$($minor)"
                    Write-Host "  Fix: Update Rust with 'rustup update'" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Error "Cargo not found"
            Write-Host "  Fix: Install Rust from https://rustup.rs/" -ForegroundColor Yellow
            Write-Host "       Or use winget: winget install Rustlang.Rust.MSVC" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Cargo not found or not accessible"
        Write-Host "  Fix: Install Rust from https://rustup.rs/" -ForegroundColor Yellow
    }

    # Test rustc
    try {
        $rustcVersion = rustc --version 2>$null
        if ($rustcVersion) {
            Write-Pass "Rust compiler found: $rustcVersion"
        } else {
            Write-Error "Rust compiler (rustc) not found"
            Write-Host "  Fix: Install Rust from https://rustup.rs/" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Rust compiler (rustc) not found"
        Write-Host "  Fix: Install Rust from https://rustup.rs/" -ForegroundColor Yellow
    }
}

function Test-GitInstallation {
    Write-Host "Testing Git installation..." -ForegroundColor White
    
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            Write-Pass "Git found: $gitVersion"
            
            # Test git configuration
            try {
                $userName = git config --global user.name 2>$null
                if ($userName) {
                    Write-Pass "Git is configured"
                } else {
                    Write-Warning "Git user not configured"
                    Write-Host "  Recommendation: Configure git with:" -ForegroundColor Yellow
                    Write-Host "    git config --global user.name 'Your Name'" -ForegroundColor Yellow
                    Write-Host "    git config --global user.email 'your.email@example.com'" -ForegroundColor Yellow
                }
            } catch {
                Write-Warning "Could not check git configuration"
            }
        } else {
            Write-Error "Git not found"
            Write-Host "  Fix: Install git:" -ForegroundColor Yellow
            Write-Host "    Download from https://git-scm.com/download/win" -ForegroundColor Yellow
            Write-Host "    Or use winget: winget install Git.Git" -ForegroundColor Yellow
            Write-Host "    Or use chocolatey: choco install git" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Git not found"
        Write-Host "  Fix: Install git from https://git-scm.com/download/win" -ForegroundColor Yellow
    }
}

function Test-Permissions {
    Write-Host "Testing file system permissions..." -ForegroundColor White
    
    # Test current directory write permissions
    $testFile = "./test_write_permissions.tmp"
    try {
        New-Item -Path $testFile -ItemType File -Force | Out-Null
        Remove-Item -Path $testFile -Force
        Write-Pass "Current directory is writable"
    } catch {
        Write-Error "Cannot write to current directory"
        Write-Host "  Fix: Ensure you have write permissions to $(Get-Location)" -ForegroundColor Yellow
    }
    
    # Test log directory creation
    $logDir = "C:\GitLogs\test"
    
    Write-Host "Testing log directory creation at: $logDir" -ForegroundColor White
    try {
        if (!(Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $testLogFile = Join-Path $logDir "test.log"
        New-Item -Path $testLogFile -ItemType File -Force | Out-Null
        Remove-Item -Path $testLogFile -Force
        Remove-Item -Path $logDir -Force -Recurse
        Write-Pass "Can create and write to log directory"
    } catch {
        Write-Error "Cannot create or write to log directory: $logDir"
        Write-Host "  Fix: Ensure write permissions to the log directory or run as Administrator" -ForegroundColor Yellow
    }
}

function Test-WindowsRequirements {
    Write-Host "Testing Windows-specific requirements..." -ForegroundColor White
    
    # Test PowerShell versions
    Write-Pass "PowerShell found: $($PSVersionTable.PSVersion)"
    
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-Pass "PowerShell version is compatible (>= 5.0)"
    } else {
        Write-Error "PowerShell version too old. Need 5.0 or higher"
        Write-Host "  Fix: Update Windows PowerShell or install PowerShell Core" -ForegroundColor Yellow
    }
    
    # Test if running as administrator
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Write-Pass "Running with administrator privileges"
    } else {
        Write-Warning "Not running as administrator"
        Write-Host "  Note: Administrator privileges required for system service installation" -ForegroundColor Yellow
        Write-Host "  Fix: Run installer as Administrator for full functionality" -ForegroundColor Yellow
    }
    
    # Test Windows Service Control Manager
    try {
        $services = Get-Service | Select-Object -First 1
        if ($services) {
            Write-Pass "Windows Service Control Manager accessible"
        }
    } catch {
        Write-Error "Cannot access Windows Service Control Manager"
        Write-Host "  Fix: Run as Administrator or check Windows services" -ForegroundColor Yellow
    }
    
    # Test common shells
    $shells = @(
        @{Name="PowerShell"; Command="powershell"},
        @{Name="PowerShell Core"; Command="pwsh"},
        @{Name="Command Prompt"; Command="cmd"}
    )
    
    $shellsFound = 0
    foreach ($shell in $shells) {
        try {
            if (Get-Command $shell.Command -ErrorAction SilentlyContinue) {
                Write-Pass "Shell found: $($shell.Name)"
                $shellsFound++
            }
        } catch {
            # Shell not found, continue
        }
    }
    
    if ($shellsFound -eq 0) {
        Write-Error "No supported shells found"
    }
}

function Test-NetworkRequirements {
    Write-Host "Testing network requirements..." -ForegroundColor White
    
    # No network needed for core functionality
    Write-Pass "No network requirements (local operation only)"
    
    # Test internet for crate dependencies during build
    try {
        $ping = Test-Connection -ComputerName "crates.io" -Count 1 -Quiet 2>$null
        if ($ping) {
            Write-Pass "Internet connectivity (needed for Rust dependencies)"
        } else {
            Write-Warning "No internet connectivity"
            Write-Host "  Note: Internet required for initial build (Rust crates)" -ForegroundColor Yellow
            Write-Host "  Fix: Ensure internet access or use offline build" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Could not test internet connectivity"
        Write-Host "  Note: Internet may be required for Rust dependencies" -ForegroundColor Yellow
    }
}

function Test-BuildRequirements {
    Write-Host "Testing build requirements..." -ForegroundColor White
    
    # Test if we can compile a basic Rust project
    $tempDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
    
    try {
        New-Item -Path $tempDir -ItemType Directory | Out-Null
        Push-Location $tempDir
        
        try {
            cargo init test-project --name test *>$null
            Push-Location "test-project"
            cargo check *>$null
            Write-Pass "Rust compilation works"
        } catch {
            Write-Error "Rust compilation failed"
            Write-Host "  Fix: Check Rust installation or try: rustup update" -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Build test failed: $($_.Exception.Message)"
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Main {
    Write-Host "Git Monitor - Installation Requirements Test" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
    
    Test-RustToolchain
    Write-Host ""
    
    Test-GitInstallation
    Write-Host ""
    
    Test-Permissions
    Write-Host ""
    
    Test-WindowsRequirements
    Write-Host ""
    
    Test-NetworkRequirements
    Write-Host ""
    
    Test-BuildRequirements
    Write-Host ""
    
    # Summary
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "Test Summary:" -ForegroundColor White
    Write-Host "  Passed: $Global:PassedTests" -ForegroundColor Green
    
    if ($Global:Warnings -gt 0) {
        Write-Host "  Warnings: $Global:Warnings" -ForegroundColor Yellow
    }
    
    if ($Global:FailedTests -gt 0) {
        Write-Host "  Failed: $Global:FailedTests" -ForegroundColor Red
        Write-Host ""
        Write-Host "Installation requirements not met!" -ForegroundColor Red
        Write-Host "Please fix the failed tests before proceeding with installation." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host ""
        if ($Global:Warnings -gt 0) {
            Write-Host "Installation requirements mostly satisfied with warnings." -ForegroundColor Yellow
            Write-Host "You may proceed, but some features might not work optimally." -ForegroundColor Yellow
        } else {
            Write-Host "All installation requirements satisfied!" -ForegroundColor Green
            Write-Host "Ready to proceed with installation." -ForegroundColor Green
        }
        exit 0
    }
}

# Run the tests
Main