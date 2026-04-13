@echo off
REM Git Monitor Binary Installation Batch Script
REM Simple installer for Windows users who prefer batch files

setlocal enabledelayedexpansion

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\GitMonitor"
set "CONFIG_DIR=%APPDATA%\git-monitor"

echo Git Monitor Binary Installer
echo =============================
echo.

REM Check prerequisites
echo [INFO] Checking prerequisites...

REM Check for git
git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git not found
    echo.
    echo Please install Git first:
    echo   winget install Git.Git
    echo   Or download from https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)
echo [SUCCESS] Git found

REM Check for executable
if not exist "git-monitor.exe" (
    echo [ERROR] git-monitor.exe not found in current directory
    echo Please ensure you've extracted the binary distribution correctly
    echo.
    pause
    exit /b 1
)
echo [SUCCESS] git-monitor.exe found

REM Create installation directory
echo.
echo [INFO] Installing Git Monitor executable...
mkdir "%INSTALL_DIR%" 2>nul
copy "git-monitor.exe" "%INSTALL_DIR%\git-monitor.exe" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy executable
    pause
    exit /b 1
)
echo [SUCCESS] Installed executable to %INSTALL_DIR%

REM Copy default config if available
if exist "git-monitor.json" (
    copy "git-monitor.json" "%INSTALL_DIR%\default-config.json" >nul
    echo [INFO] Copied default configuration
)

REM Check and update PATH
echo.
echo [INFO] Checking PATH configuration...
echo %PATH% | find "%INSTALL_DIR%" >nul
if errorlevel 1 (
    echo [INFO] Adding %INSTALL_DIR% to user PATH...
    
    REM Get current user PATH
    for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set "USER_PATH=%%b"
    
    REM Add to PATH if not empty
    if defined USER_PATH (
        set "NEW_PATH=%USER_PATH%;%INSTALL_DIR%"
    ) else (
        set "NEW_PATH=%INSTALL_DIR%"
    )
    
    REM Update registry
    reg add "HKCU\Environment" /v PATH /t REG_EXPAND_SZ /d "!NEW_PATH!" /f >nul
    if not errorlevel 1 (
        echo [SUCCESS] Added to PATH ^(restart terminal to take effect^)
    ) else (
        echo [WARN] Failed to update PATH automatically
        echo You may need to add %INSTALL_DIR% to your PATH manually
    )
) else (
    echo [INFO] Already in PATH
)

REM Create configuration
echo.
echo [INFO] Creating user configuration...
mkdir "%CONFIG_DIR%" 2>nul

REM Get hostname
set "HOSTNAME=%COMPUTERNAME%"
if not defined HOSTNAME set "HOSTNAME=unknown"

REM Create log directory
set "LOG_DIR=%USERPROFILE%\.local\share\git-monitor"
mkdir "%LOG_DIR%" 2>nul

REM Create basic config file
set "CONFIG_PATH=%CONFIG_DIR%\config.json"
if not exist "%CONFIG_PATH%" (
    (
        echo {
        echo   "logPath": "%LOG_DIR:\=\\%\\%HOSTNAME%_githistory.log",
        echo   "deviceNickname": "%HOSTNAME%",
        echo   "enabledShells": ["powershell", "cmd"],
        echo   "monitorScope": "user",
        echo   "logRotation": {
        echo     "enabled": true,
        echo     "maxSizeMb": 100,
        echo     "keepFiles": 10
        echo   },
        echo   "performance": {
        echo     "maxMemoryMb": 10,
        echo     "logBufferSize": 1000,
        echo     "flushIntervalSeconds": 30
        echo   }
        echo }
    ) > "%CONFIG_PATH%"
    echo [SUCCESS] Created configuration at %CONFIG_PATH%
    echo [INFO] Log will be written to: %LOG_DIR%\%HOSTNAME%_githistory.log
) else (
    echo [INFO] Configuration already exists at %CONFIG_PATH%
)

REM Test installation
echo.
echo [INFO] Testing installation...
"%INSTALL_DIR%\git-monitor.exe" --help >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Installation test failed
    pause
    exit /b 1
)
echo [SUCCESS] Installation test passed

REM Optional service installation
echo.
echo Git Monitor installation is complete!
echo.
echo To install as a Windows service ^(requires Administrator^):
echo   1. Right-click Command Prompt or PowerShell
echo   2. Select "Run as administrator"  
echo   3. Run: git-monitor install
echo.
echo Quick Start:
echo   1. Restart your terminal ^(to refresh PATH^)
echo   2. Test: git-monitor run --verbose
echo   3. Run some git commands in another terminal
echo   4. Check your log file for entries
echo.
echo Commands:
echo   git-monitor run --verbose    # Test in foreground
echo   git-monitor status           # Check service status  
echo   git-monitor start/stop       # Control service
echo   git-monitor --help           # Full command list
echo.
echo Configuration:
echo   Edit: %CONFIG_PATH%
echo.
echo Getting Help:
echo   https://github.com/Cerebellum-Lab/git-log-access
echo.

pause
