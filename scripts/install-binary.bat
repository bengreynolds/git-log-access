@echo off
REM Git Monitor Binary Installation Batch Script
REM Simple installer for Windows users who prefer batch files
REM 
REM Usage:
REM   install.bat           - Interactive installation with configuration prompts
REM   install.bat SILENT    - Silent installation with default settings

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "INSTALL_DIR=%LOCALAPPDATA%\Programs\GitMonitor"
set "CONFIG_DIR=%APPDATA%\git-monitor"
if defined GIT_MONITOR_INSTALL_DIR set "INSTALL_DIR=%GIT_MONITOR_INSTALL_DIR%"
if defined GIT_MONITOR_CONFIG_DIR set "CONFIG_DIR=%GIT_MONITOR_CONFIG_DIR%"
set "SKIP_PATH_UPDATE=false"
if /i "%GIT_MONITOR_SKIP_PATH_UPDATE%"=="true" set "SKIP_PATH_UPDATE=true"
set "NO_SERVICE=false"
if /i "%GIT_MONITOR_NO_SERVICE%"=="true" set "NO_SERVICE=true"
set "NO_PAUSE=false"
if /i "%GIT_MONITOR_NO_PAUSE%"=="true" set "NO_PAUSE=true"

REM Check for silent installation
set "SILENT_INSTALL=false"
if /i "%1"=="SILENT" set "SILENT_INSTALL=true"
set "KEEP_EXISTING_CONFIG=false"

echo Git Monitor Binary Installer
echo =============================
echo.
echo [INFO] Package directory: %SCRIPT_DIR%
echo [INFO] Source executable: %SCRIPT_DIR%git-monitor.exe
echo [INFO] Install directory: %INSTALL_DIR%
echo [INFO] Config directory: %CONFIG_DIR%
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
if not exist "%SCRIPT_DIR%git-monitor.exe" (
    echo [ERROR] git-monitor.exe not found in current directory
    echo Please ensure you've extracted the binary distribution correctly
    echo.
    pause
    exit /b 1
)
echo [SUCCESS] git-monitor.exe found

echo [INFO] Removing download security blocks from package files...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$files = @('%SCRIPT_DIR%git-monitor.exe','%SCRIPT_DIR%git-monitor.json','%SCRIPT_DIR%install.bat','%SCRIPT_DIR%install.ps1') | Where-Object { Test-Path $_ }; foreach ($file in $files) { try { Unblock-File -LiteralPath $file -ErrorAction Stop; Write-Output ('[INFO] Unblocked ' + $file) } catch { Write-Output ('[INFO] Could not unblock ' + $file + ': ' + $_.Exception.Message) } }"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$source = '%SCRIPT_DIR%git-monitor.exe'; try { $stream = [System.IO.File]::Open($source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite); $stream.Dispose(); exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }" > "%TEMP%\git-monitor-install-source-check.txt" 2>&1
if errorlevel 1 (
    echo [ERROR] git-monitor.exe exists but cannot be read
    type "%TEMP%\git-monitor-install-source-check.txt"
    echo [WARN] Windows is blocking access to the downloaded executable
    echo [WARN] Move the extracted folder outside Downloads or unblock the ZIP/executable, then retry.
    if not "%NO_PAUSE%"=="true" pause
    exit /b 1
)
del "%TEMP%\git-monitor-install-source-check.txt" >nul 2>&1

REM Detect and overwrite existing installation state
set "EXISTING_INSTALL=false"
if exist "%INSTALL_DIR%\git-monitor.exe" set "EXISTING_INSTALL=true"
if exist "%CONFIG_DIR%\config.json" set "EXISTING_INSTALL=true"

for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$scriptExe = [System.IO.Path]::GetFullPath('%SCRIPT_DIR%git-monitor.exe'); $matches = @(Get-Command git-monitor -All -ErrorAction SilentlyContinue | Where-Object { $_.Source -and ([System.IO.Path]::GetFullPath($_.Source) -ne $scriptExe) } | Select-Object -ExpandProperty Source -Unique); $matches | ForEach-Object { Write-Output $_ }" 2^>nul`) do (
    if not defined COMMAND_IN_PATH set "COMMAND_IN_PATH=true"
    if not defined RESOLVED_COMMAND_PATHS (
        set "RESOLVED_COMMAND_PATHS=%%A"
    ) else (
        set "RESOLVED_COMMAND_PATHS=!RESOLVED_COMMAND_PATHS!;%%A"
    )
)

if "%EXISTING_INSTALL%"=="true" (
    echo.
    echo [WARN] Existing Git Monitor installation detected
    if exist "%INSTALL_DIR%\git-monitor.exe" echo [WARN] Existing executable: %INSTALL_DIR%\git-monitor.exe
    if exist "%CONFIG_DIR%\config.json" echo [WARN] Existing config: %CONFIG_DIR%\config.json
    if defined COMMAND_IN_PATH echo [WARN] git-monitor command is already available in PATH
    if defined COMMAND_IN_PATH (
        echo [INFO] git-monitor resolves to:
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$paths = '%RESOLVED_COMMAND_PATHS%'.Split(';') | Where-Object { $_ }; $paths | ForEach-Object { Write-Output $_ }"
    )
    echo [INFO] Overwriting previous installation...

    if exist "%INSTALL_DIR%" (
        echo [INFO] Existing install directory contents before cleanup:
        dir "%INSTALL_DIR%" /a
        rmdir /s /q "%INSTALL_DIR%" >nul 2>&1
        if exist "%INSTALL_DIR%" (
            echo [WARN] Install directory still exists after cleanup attempt: %INSTALL_DIR%
        ) else (
            echo [INFO] Existing install directory removed
        )
    )
)

echo [INFO] Stopping running Git Monitor processes...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$exe = '%INSTALL_DIR%\git-monitor.exe'; if (Test-Path $exe) { try { & $exe stop 2>$null | Out-Null } catch {} }; Get-Command git-monitor -All -ErrorAction SilentlyContinue | Where-Object { $_.Source } | Select-Object -ExpandProperty Source -Unique | ForEach-Object { try { & $_ stop 2>$null | Out-Null } catch {} }; Start-Sleep -Milliseconds 500; $stopped = 0; $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'git-monitor.exe' }); foreach ($proc in $procs) { try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue; $stopped += 1 } catch {} }; Write-Output ('[INFO] Stop requested for ' + $stopped + ' Git Monitor process(es)'); for ($i = 0; $i -lt 20; $i++) { $still = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'git-monitor.exe' } | Select-Object -First 1; if (-not $still) { Write-Output '[INFO] No Git Monitor processes remain running'; exit 0 }; Start-Sleep -Milliseconds 250 }; Write-Output '[WARN] Git Monitor process is still running after shutdown attempts'" 

REM Create installation directory
echo.
echo [INFO] Installing Git Monitor executable...
mkdir "%INSTALL_DIR%" 2>nul
if exist "%INSTALL_DIR%" (
    echo [INFO] Install directory is present: %INSTALL_DIR%
) else (
    echo [WARN] Install directory could not be created: %INSTALL_DIR%
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$source = '%SCRIPT_DIR%git-monitor.exe'; $destination = '%INSTALL_DIR%\git-monitor.exe'; Write-Output ('[INFO] Copy source: ' + $source); Write-Output ('[INFO] Copy destination: ' + $destination); Write-Output ('[INFO] Source exists: ' + (Test-Path $source)); Write-Output ('[INFO] Destination parent exists: ' + (Test-Path (Split-Path -Parent $destination))); $copied = $false; for ($i = 0; $i -lt 20; $i++) { try { Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop; Write-Output ('[INFO] Copy succeeded on attempt ' + ($i + 1)); $copied = $true; break } catch { $message = $_.Exception.Message; Write-Output ('[WARN] Copy attempt ' + ($i + 1) + ' failed: ' + $message); Start-Sleep -Milliseconds 500 } }; if (-not $copied) { if (Test-Path (Split-Path -Parent $destination)) { Write-Output '[INFO] Destination parent details:'; Get-Item (Split-Path -Parent $destination) | Format-List FullName,Attributes,Mode | Out-String | Write-Output; Get-ChildItem -Force (Split-Path -Parent $destination) | Select-Object FullName,Length,Mode | Format-Table -AutoSize | Out-String | Write-Output }; Write-Output ('[ERROR] Final copy failure: ' + $message); exit 1 }" > "%TEMP%\git-monitor-install-copy-error.txt" 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to copy executable
    type "%TEMP%\git-monitor-install-copy-error.txt"
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$source = '%SCRIPT_DIR%git-monitor.exe'; try { $stream = [System.IO.File]::Open($source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite); $stream.Dispose(); Write-Output '[INFO] Source readable after copy failure: True' } catch { Write-Output ('[WARN] Source readable after copy failure: False - ' + $_.Exception.Message) }"
    if exist "%INSTALL_DIR%\git-monitor.exe" echo [WARN] Target executable still exists: %INSTALL_DIR%\git-monitor.exe
    pause
    exit /b 1
)
del "%TEMP%\git-monitor-install-copy-error.txt" >nul 2>&1
echo [SUCCESS] Installed executable to %INSTALL_DIR%

REM Copy default config if available
if exist "%SCRIPT_DIR%git-monitor.json" (
    copy "%SCRIPT_DIR%git-monitor.json" "%INSTALL_DIR%\default-config.json" >nul
    echo [INFO] Copied default configuration
)

REM Check and update PATH
echo.
echo [INFO] Checking PATH configuration...
if "%SKIP_PATH_UPDATE%"=="true" (
    echo [INFO] Skipping PATH update because GIT_MONITOR_SKIP_PATH_UPDATE=true
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$userPath = [Environment]::GetEnvironmentVariable('Path', 'User'); $processPath = $env:PATH; if (($userPath -and $userPath.Contains('%INSTALL_DIR%')) -or ($processPath -and $processPath.Contains('%INSTALL_DIR%'))) { exit 0 } else { exit 1 }" >nul 2>&1
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
)

REM Configuration setup
set "DEFAULT_NICKNAME=%COMPUTERNAME%"
if not defined DEFAULT_NICKNAME set "DEFAULT_NICKNAME=my-computer"
set "DEFAULT_LOG_DIR=%USERPROFILE%\.local\share\git-monitor"
set "DEFAULT_MAX_SIZE_MB=100"
set "EXISTING_CONFIG_PATH=%CONFIG_DIR%\config.json"

if exist "%EXISTING_CONFIG_PATH%" (
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$cfg = Get-Content -LiteralPath '%EXISTING_CONFIG_PATH%' -Raw | ConvertFrom-Json; $device = if ([string]::IsNullOrWhiteSpace($cfg.deviceNickname)) { $env:COMPUTERNAME } else { $cfg.deviceNickname }; if ([string]::IsNullOrWhiteSpace($device)) { $device = 'my-computer' }; Write-Output $device" 2^>nul`) do set "DEFAULT_NICKNAME=%%A"
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$cfg = Get-Content -LiteralPath '%EXISTING_CONFIG_PATH%' -Raw | ConvertFrom-Json; $logDir = Split-Path -Path $cfg.logPath -Parent; if ([string]::IsNullOrWhiteSpace($logDir)) { $logDir = Join-Path $env:USERPROFILE '.local\share\git-monitor' }; Write-Output $logDir" 2^>nul`) do set "DEFAULT_LOG_DIR=%%A"
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$cfg = Get-Content -LiteralPath '%EXISTING_CONFIG_PATH%' -Raw | ConvertFrom-Json; $maxSize = if ($cfg.logRotation -and $cfg.logRotation.maxSizeMb) { [int]$cfg.logRotation.maxSizeMb } else { 100 }; Write-Output $maxSize" 2^>nul`) do set "DEFAULT_MAX_SIZE_MB=%%A"
)

if "%SILENT_INSTALL%"=="true" (
    if exist "%EXISTING_CONFIG_PATH%" (
        echo [INFO] Silent installation - keeping existing configuration...
        set "KEEP_EXISTING_CONFIG=true"
    ) else (
        echo [INFO] Silent installation - using defaults...
    )

    set "DEVICE_NICKNAME=%DEFAULT_NICKNAME%"
    set "USER_LOG_DIR=%DEFAULT_LOG_DIR%"
    set "MAX_SIZE_MB=%DEFAULT_MAX_SIZE_MB%"

    echo [INFO] Device nickname: !DEVICE_NICKNAME!
    echo [INFO] Log directory: !USER_LOG_DIR!
) else (
    REM Interactive configuration setup
    echo.
    echo === Git Monitor Configuration ===
    echo Please provide your preferences for Git Monitor setup
    echo.

    if exist "%EXISTING_CONFIG_PATH%" (
        echo Existing configuration detected:
        echo   Device Nickname: !DEFAULT_NICKNAME!
        echo   Log Directory: !DEFAULT_LOG_DIR!
        echo   Max Log Size: !DEFAULT_MAX_SIZE_MB!MB
        echo.
        set /p "KEEP_CONFIG_RESPONSE=Keep existing configuration? [Y/n]: "
        if /i not "!KEEP_CONFIG_RESPONSE!"=="n" if /i not "!KEEP_CONFIG_RESPONSE!"=="no" (
            set "KEEP_EXISTING_CONFIG=true"
        )
    )

    set "DEVICE_NICKNAME=!DEFAULT_NICKNAME!"
    set "USER_LOG_DIR=!DEFAULT_LOG_DIR!"
    set "MAX_SIZE_MB=!DEFAULT_MAX_SIZE_MB!"

    if "!KEEP_EXISTING_CONFIG!"=="true" (
        echo [INFO] Keeping existing configuration values.
    ) else (
        REM Device nickname
        set /p "DEVICE_NICKNAME=Device nickname [!DEFAULT_NICKNAME!]: "
        if not defined DEVICE_NICKNAME set "DEVICE_NICKNAME=!DEFAULT_NICKNAME!"

        REM Log directory
        echo.
        echo Log Directory:
        echo   Where git command logs will be stored
        set /p "USER_LOG_DIR=Log directory [!DEFAULT_LOG_DIR!]: "
        if not defined USER_LOG_DIR set "USER_LOG_DIR=!DEFAULT_LOG_DIR!"

        REM Log rotation
        echo.
        echo Log Rotation:
        echo   Automatically rotate logs when they get too large
        set /p "MAX_SIZE_MB=Maximum log file size in MB [!DEFAULT_MAX_SIZE_MB!]: "
        if not defined MAX_SIZE_MB set "MAX_SIZE_MB=!DEFAULT_MAX_SIZE_MB!"

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
)

set "CONFIG_PATH=%CONFIG_DIR%\config.json"
set "LOG_FILE_PATH=%USER_LOG_DIR%\%DEVICE_NICKNAME%_githistory.log"

echo.
if "%KEEP_EXISTING_CONFIG%"=="true" (
    echo [INFO] Keeping existing configuration...
    echo [SUCCESS] Using existing configuration at %CONFIG_PATH%
) else (
    REM Create directories
    mkdir "%CONFIG_DIR%" 2>nul
    mkdir "%USER_LOG_DIR%" 2>nul

    if exist "%CONFIG_PATH%" (
        for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $backup = Join-Path '%CONFIG_DIR%' ('config.' + $timestamp + '.backup.json'); Copy-Item -LiteralPath '%CONFIG_PATH%' -Destination $backup -Force; Write-Output $backup" 2^>nul`) do set "CONFIG_BACKUP_PATH=%%A"
        if defined CONFIG_BACKUP_PATH (
            echo [SUCCESS] Backed up existing configuration to !CONFIG_BACKUP_PATH!
        ) else (
            echo [WARN] Existing configuration was detected but backup creation failed
        )
    )

    REM Create configuration
    echo [INFO] Creating configuration...
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

REM Enable monitoring unless silent mode is intended to stay passive
echo.
if "%NO_SERVICE%"=="true" (
    echo [INFO] Skipping shell hooks and background monitor because GIT_MONITOR_NO_SERVICE=true
) else (
    echo [INFO] Enabling shell hooks and background monitor...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$p = Start-Process -FilePath '%INSTALL_DIR%\git-monitor.exe' -ArgumentList 'start' -WindowStyle Hidden -PassThru; if ($p.WaitForExit(10000)) { $p.Refresh(); exit $p.ExitCode } else { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; exit 124 }" >nul 2>&1
    if errorlevel 124 (
        echo [WARN] Automatic activation did not complete within 10 seconds
        echo [INFO] You can enable it later with: git-monitor start
    ) else if errorlevel 1 (
        echo [WARN] Automatic activation failed
        echo [INFO] You can enable it later with: git-monitor start
    ) else (
        echo [SUCCESS] Monitoring enabled
        echo [INFO] Automatic sign-in startup was configured for the background monitor
        echo [INFO] Open a new PowerShell or pwsh window to load the installed profile hook
    )
)

echo.
if "%NO_SERVICE%"=="true" (
    echo [INFO] Skipping post-install self-check because GIT_MONITOR_NO_SERVICE=true
) else (
    echo [INFO] Running post-install self-check...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$exe = '%INSTALL_DIR%\git-monitor.exe'; $cfgPath = '%CONFIG_PATH%'; if (-not (Test-Path $cfgPath)) { Write-Output '[WARN] Self-check skipped because config.json was not found'; exit 0 }; Write-Output '  Status:'; & $exe status 2>&1 | ForEach-Object { Write-Output ('    ' + $_) }; $logPath = try { (Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json).logPath } catch { $null }; $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('git-monitor-install-check-' + [guid]::NewGuid().ToString('N')); New-Item -Path $tempRepo -ItemType Directory -Force | Out-Null; try { git init --quiet $tempRepo | Out-Null; & $exe capture --config $cfgPath --shell powershell --cwd $tempRepo --parent-pid $PID -- status 2>$null | Out-Null; Start-Sleep -Milliseconds 250 } finally { Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue }; if ($logPath) { Write-Output ('  Detected log path: ' + $logPath); if (Test-Path $logPath) { $latest = Get-Content -LiteralPath $logPath | Select-Object -Last 1; if ($latest) { Write-Output ('  Latest log entry: ' + $latest) } else { Write-Output '[WARN] Log file exists but no entries were found after self-check' } } else { Write-Output '[WARN] Log file was not created during self-check' } } else { Write-Output '[WARN] Could not determine configured log path for self-check' }"
)

echo.
echo Git Monitor installation is complete!
echo.
if not "%NO_SERVICE%"=="true" echo Automatic sign-in startup was configured for the background monitor.
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
echo   https://github.com/Cerebellum-Lab/git-log-access
echo.

if not "%SILENT_INSTALL%"=="true" if not "%NO_PAUSE%"=="true" pause
