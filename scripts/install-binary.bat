@echo off
REM Git Monitor Binary Installation Batch Script
REM Simple installer for Windows users who prefer batch files
REM 
REM Usage:
REM   install.bat           - Interactive installation with configuration prompts
REM   install.bat SILENT    - Silent installation with default settings

setlocal enabledelayedexpansion

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\GitMonitor"
set "CONFIG_DIR=%APPDATA%\git-monitor"

REM Check for silent installation
set "SILENT_INSTALL=false"
if /i "%1"=="SILENT" set "SILENT_INSTALL=true"

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

REM Detect and overwrite existing installation state
set "EXISTING_INSTALL=false"
if exist "%INSTALL_DIR%\git-monitor.exe" set "EXISTING_INSTALL=true"
if exist "%CONFIG_DIR%\config.json" set "EXISTING_INSTALL=true"

where git-monitor >nul 2>&1
if not errorlevel 1 set "COMMAND_IN_PATH=true"

if "%EXISTING_INSTALL%"=="true" (
    echo.
    echo [WARN] Existing Git Monitor installation detected
    if exist "%INSTALL_DIR%\git-monitor.exe" echo [WARN] Existing executable: %INSTALL_DIR%\git-monitor.exe
    if exist "%CONFIG_DIR%\config.json" echo [WARN] Existing config: %CONFIG_DIR%\config.json
    if defined COMMAND_IN_PATH echo [WARN] git-monitor command is already available in PATH
    echo [INFO] Overwriting previous installation...

    if exist "%INSTALL_DIR%\git-monitor.exe" (
        "%INSTALL_DIR%\git-monitor.exe" stop >nul 2>&1
        timeout /t 2 /nobreak >nul
    )

    if exist "%INSTALL_DIR%" (
        rmdir /s /q "%INSTALL_DIR%" >nul 2>&1
    )
)

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

REM Configuration setup
if "%SILENT_INSTALL%"=="true" (
    echo [INFO] Silent installation - using defaults...
    
    REM Use defaults for silent install
    set "DEVICE_NICKNAME=%COMPUTERNAME%"
    if not defined DEVICE_NICKNAME set "DEVICE_NICKNAME=my-computer"
    set "USER_LOG_DIR=%USERPROFILE%\.local\share\git-monitor"
    set "MAX_SIZE_MB=100"
    
    echo [INFO] Device nickname: %DEVICE_NICKNAME%
    echo [INFO] Log directory: %USER_LOG_DIR%
) else (
    REM Interactive configuration setup
    echo.
    echo === Git Monitor Configuration ===
    echo Please provide your preferences for Git Monitor setup
    echo.

    REM Device nickname
    set "DEFAULT_NICKNAME=%COMPUTERNAME%"
    if not defined DEFAULT_NICKNAME set "DEFAULT_NICKNAME=my-computer"
    set /p "DEVICE_NICKNAME=Device nickname [!DEFAULT_NICKNAME!]: "
    if not defined DEVICE_NICKNAME set "DEVICE_NICKNAME=!DEFAULT_NICKNAME!"

    REM Log directory  
    set "DEFAULT_LOG_DIR=%USERPROFILE%\.local\share\git-monitor"
    echo.
    echo Log Directory:
    echo   Where git command logs will be stored
    set /p "USER_LOG_DIR=Log directory [!DEFAULT_LOG_DIR!]: "
    if not defined USER_LOG_DIR set "USER_LOG_DIR=!DEFAULT_LOG_DIR!"

    REM Log rotation
    echo.
    echo Log Rotation:
    echo   Automatically rotate logs when they get too large
    set /p "MAX_SIZE_MB=Maximum log file size in MB [100]: "
    if not defined MAX_SIZE_MB set "MAX_SIZE_MB=100"

    REM Confirmation
    echo.
    echo === Configuration Summary ===
    echo Device Nickname: !DEVICE_NICKNAME!
    echo Log Directory: !USER_LOG_DIR!
    echo Log File: !USER_LOG_DIR!\!DEVICE_NICKNAME!_githistory.log
    echo Max Log Size: !MAX_SIZE_MB!MB
    echo.
    set /p "CONFIRM=Continue with this configuration? [Y/n]: "
    if /i "!CONFIRM!"=="n" (
        echo Configuration cancelled by user
        pause
        exit /b 1
    )
)

REM Create directories
mkdir "%CONFIG_DIR%" 2>nul
mkdir "%USER_LOG_DIR%" 2>nul

REM Create configuration
echo.
echo [INFO] Creating configuration...

REM Create basic config file
set "CONFIG_PATH=%CONFIG_DIR%\config.json"
set "LOG_FILE_PATH=%USER_LOG_DIR%\%DEVICE_NICKNAME%_githistory.log"
(
    echo {
    echo   "logPath": "%LOG_FILE_PATH:\=\\%",
    echo   "deviceNickname": "%DEVICE_NICKNAME%",
    echo   "enabledShells": ["powershell", "pwsh"],
    echo   "monitorScope": "user",
    echo   "logRotation": {
    echo     "enabled": true,
    echo     "maxSizeMb": %MAX_SIZE_MB%,
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
echo [SUCCESS] Log will be written to: %LOG_FILE_PATH%

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

REM Enable monitoring unless silent mode is intended to stay passive
echo.
echo [INFO] Enabling shell hooks and background monitor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Start-Process -FilePath '%INSTALL_DIR%\git-monitor.exe' -ArgumentList 'start' -PassThru; if ($p.WaitForExit(5000)) { exit $p.ExitCode } else { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; exit 124 }" >nul 2>&1
if errorlevel 124 (
    echo [WARN] Automatic activation did not complete within 5 seconds
    echo [INFO] You can enable it later with: git-monitor start
) else if errorlevel 1 (
    echo [WARN] Automatic activation failed
    echo [INFO] You can enable it later with: git-monitor start
) else (
    echo [SUCCESS] Monitoring enabled
    echo [INFO] Open a new PowerShell or pwsh window to load the installed profile hook
)

echo.
echo Git Monitor installation is complete!
echo.
echo Next steps:
echo   1. Open a new terminal ^(to refresh PATH and load shell profile changes^)
echo   2. Run: git-monitor status
echo   3. Run some git commands in a repository
echo   4. Check your log file for entries
echo.
echo Commands:
echo   git-monitor start            # Enable hooks and start the background monitor
echo   git-monitor stop             # Disable hooks and stop the background monitor
echo   git-monitor status           # Show hook and daemon status
echo   git-monitor run --verbose    # Foreground smoke test
echo   git-monitor --help           # Full command list
echo.
echo Configuration:
echo   Edit: %CONFIG_PATH%
echo.
echo Installation Options:
echo   install.bat           # Interactive setup ^(what you just used^)
echo   install.bat SILENT    # Automated setup with defaults
echo.
echo Getting Help:
echo   https://github.com/bengreynolds/git-log-access
echo.

if not "%SILENT_INSTALL%"=="true" pause
