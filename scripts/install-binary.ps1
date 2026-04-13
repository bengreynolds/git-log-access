# Git Monitor Binary Installation Script (PowerShell)
# This script installs the pre-compiled binary (no compilation required)

param(
    [string]$InstallDir = $(if ($env:GIT_MONITOR_INSTALL_DIR) { $env:GIT_MONITOR_INSTALL_DIR } else { "$env:LOCALAPPDATA\Programs\GitMonitor" }),
    [string]$ConfigDir = $(if ($env:GIT_MONITOR_CONFIG_DIR) { $env:GIT_MONITOR_CONFIG_DIR } else { "$env:APPDATA\git-monitor" }),
    [switch]$Force = $false,
    [switch]$NoService = $false,
    [switch]$Silent = $false,
    [switch]$SkipPathUpdate = $false
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

function Write-DebugInfo($Message) {
    Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray
}

function Get-ExePath {
    return Join-Path $InstallDir "git-monitor.exe"
}

function Get-ScriptAssetPath {
    param(
        [string]$FileName
    )

    return Join-Path $PSScriptRoot $FileName
}

function Unblock-PackageFiles {
    Write-Info "Removing download security blocks from package files..."

    $files = @(
        Get-ScriptAssetPath "git-monitor.exe",
        Get-ScriptAssetPath "git-monitor.json",
        Get-ScriptAssetPath "install.ps1",
        Get-ScriptAssetPath "install.bat"
    ) | Where-Object { Test-Path $_ }

    foreach ($file in $files) {
        try {
            Unblock-File -LiteralPath $file -ErrorAction Stop
            Write-DebugInfo "Unblocked $file"
        } catch {
            Write-DebugInfo "Could not unblock ${file}: $($_.Exception.Message)"
        }
    }
}

function Test-ReadableFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Dispose()
        return $true
    } catch {
        return $false
    }
}

function Get-ExistingConfiguration {
    $configPath = Join-Path $ConfigDir "config.json"
    if (!(Test-Path $configPath)) {
        return $null
    }

    try {
        $rawConfig = Get-Content $configPath -Raw | ConvertFrom-Json
        $deviceNickname = $rawConfig.deviceNickname
        if ([string]::IsNullOrWhiteSpace($deviceNickname)) {
            $deviceNickname = $env:COMPUTERNAME
        }
        if ([string]::IsNullOrWhiteSpace($deviceNickname)) {
            $deviceNickname = "my-computer"
        }

        $logPath = $rawConfig.logPath
        $logDir = $null
        if (![string]::IsNullOrWhiteSpace($logPath)) {
            $logDir = Split-Path -Path $logPath -Parent
        }
        if ([string]::IsNullOrWhiteSpace($logDir)) {
            $logDir = "$env:USERPROFILE\.local\share\git-monitor"
        }

        $maxSizeMb = 100
        if ($rawConfig.logRotation -and $rawConfig.logRotation.maxSizeMb) {
            $maxSizeMb = [int]$rawConfig.logRotation.maxSizeMb
        }

        return @{
            DeviceNickname = $deviceNickname
            LogDir = $logDir
            MaxSizeMb = $maxSizeMb
            ConfigPath = $configPath
        }
    } catch {
        Write-Warning "Existing configuration could not be read. Defaults will be used."
        return $null
    }
}

function Backup-ExistingConfiguration {
    param(
        [string]$ConfigPath
    )

    if (!(Test-Path $ConfigPath)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path (Split-Path -Path $ConfigPath -Parent) "config.$timestamp.backup.json"
    Copy-Item -Path $ConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Get-ConfiguredLogPath {
    $configPath = Join-Path $ConfigDir "config.json"
    if (!(Test-Path $configPath)) {
        return $null
    }

    try {
        return (Get-Content $configPath -Raw | ConvertFrom-Json).logPath
    } catch {
        return $null
    }
}

function Stop-ExistingMonitorProcesses {
    $targetExePath = Get-ExePath

    Write-Info "Stopping running Git Monitor processes..."

    try {
        if (Test-Path $targetExePath) {
            & $targetExePath stop 2>$null | Out-Null
            Start-Sleep -Milliseconds 500
        }
    } catch {}

    try {
        Get-Command git-monitor -All -ErrorAction SilentlyContinue |
            Where-Object { $_.Source } |
            Select-Object -ExpandProperty Source -Unique |
            ForEach-Object {
                try {
                    & $_ stop 2>$null | Out-Null
                } catch {}
            }
        Start-Sleep -Milliseconds 500
    } catch {}

    $stoppedCount = 0
    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "git-monitor.exe"
            }

        foreach ($process in $processes) {
            try {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                $stoppedCount += 1
            } catch {}
        }
    } catch {}

    Write-DebugInfo "Stop requested for $stoppedCount Git Monitor process(es)"

    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $stillRunning = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "git-monitor.exe"
            } |
            Select-Object -First 1

        if (-not $stillRunning) {
            Write-DebugInfo "No Git Monitor processes remain running"
            break
        }

        if ($attempt -eq 19) {
            Write-Warning "Git Monitor process is still running after shutdown attempts"
        }
        Start-Sleep -Milliseconds 250
    }
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    Write-DebugInfo "Package directory: $PSScriptRoot"
    Write-DebugInfo "Source executable: $(Get-ScriptAssetPath 'git-monitor.exe')"
    Write-DebugInfo "Install directory: $InstallDir"
    Write-DebugInfo "Config directory: $ConfigDir"

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

    $sourceExePath = Get-ScriptAssetPath "git-monitor.exe"
    if (!(Test-Path $sourceExePath)) {
        Write-ErrorMsg "git-monitor.exe not found in current directory"
        Write-Host "Please ensure you've extracted the binary distribution correctly" -ForegroundColor Yellow
        return $false
    }

    Unblock-PackageFiles

    if (!(Test-ReadableFile -Path $sourceExePath)) {
        Write-ErrorMsg "git-monitor.exe exists but cannot be read"
        Write-Warning "Windows is blocking access to the downloaded executable"
        Write-Host "Move the extracted folder outside Downloads or unblock the ZIP/executable, then retry." -ForegroundColor Yellow
        return $false
    }

    Write-Success "Prerequisites check passed"
    return $true
}

function Install-Executable {
    Write-Info "Installing Git Monitor executable..."

    try {
        $sourceExePath = Get-ScriptAssetPath "git-monitor.exe"
        $targetExePath = Get-ExePath
        Write-DebugInfo "Copy source: $sourceExePath"
        Write-DebugInfo "Copy destination: $targetExePath"
        Stop-ExistingMonitorProcesses

        if (Test-Path $InstallDir) {
            Write-Info "Preparing installation directory..."
            Write-DebugInfo "Existing install directory contents:"
            Get-ChildItem -Force $InstallDir -ErrorAction SilentlyContinue | ForEach-Object {
                Write-DebugInfo "  $($_.FullName)"
            }
            Remove-Item -Path $InstallDir -Recurse -Force
            if (Test-Path $InstallDir) {
                Write-Warning "Install directory still exists after cleanup attempt: $InstallDir"
            } else {
                Write-DebugInfo "Existing install directory removed"
            }
        }

        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        Write-DebugInfo "Install directory present: $(Test-Path $InstallDir)"
        $copied = $false
        $lastCopyError = $null
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            try {
                Copy-Item -LiteralPath $sourceExePath -Destination $targetExePath -Force -ErrorAction Stop
                Write-DebugInfo "Copy succeeded on attempt $($attempt + 1)"
                $copied = $true
                break
            } catch {
                $lastCopyError = $_.Exception.Message
                Write-DebugInfo "Copy attempt $($attempt + 1) failed: $lastCopyError"
                Start-Sleep -Milliseconds 500
            }
        }

        if (-not $copied) {
            throw $lastCopyError
        }

        Write-Success "Installed executable to $(Get-ExePath)"

        $defaultConfigPath = Get-ScriptAssetPath "git-monitor.json"
        if (Test-Path $defaultConfigPath) {
            Copy-Item $defaultConfigPath (Join-Path $InstallDir "default-config.json") -Force
            Write-Info "Copied default configuration"
        }

        if ($SkipPathUpdate -or $env:GIT_MONITOR_SKIP_PATH_UPDATE -eq "true") {
            Write-Info "Skipping PATH update because SkipPathUpdate/GIT_MONITOR_SKIP_PATH_UPDATE is enabled"
        } else {
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
        }

        return $true
    } catch {
        Write-ErrorMsg "Failed to install executable: $($_.Exception.Message)"
        $targetExePath = Get-ExePath
        Write-DebugInfo "Source exists: $(Test-ReadableFile -Path (Get-ScriptAssetPath 'git-monitor.exe'))"
        Write-DebugInfo "Destination parent exists: $(Test-Path $InstallDir)"
        if (!(Test-ReadableFile -Path (Get-ScriptAssetPath 'git-monitor.exe'))) {
            Write-Warning "Source executable cannot be read. Move the extracted package out of Downloads or unblock it."
        }
        if (Test-Path $targetExePath) {
            Write-Warning "Target executable still exists at $targetExePath"
        }
        return $false
    }
}

function Get-UserConfiguration {
    $existingConfig = Get-ExistingConfiguration

    if ($Silent) {
        if ($existingConfig) {
            return @{
                DeviceNickname = $existingConfig.DeviceNickname
                LogDir = $existingConfig.LogDir
                MaxSizeMb = $existingConfig.MaxSizeMb
                KeepExisting = $true
            }
        }

        $defaultNickname = $env:COMPUTERNAME
        if (!$defaultNickname) { $defaultNickname = "my-computer" }

        return @{
            DeviceNickname = $defaultNickname
            LogDir = "$env:USERPROFILE\.local\share\git-monitor"
            MaxSizeMb = 100
            KeepExisting = $false
        }
    }

    Write-Host ""
    Write-Host "=== Git Monitor Configuration ===" -ForegroundColor $Colors.Blue
    Write-Host "Please provide your preferences for Git Monitor setup" -ForegroundColor White
    Write-Host ""

    $defaultNickname = $env:COMPUTERNAME
    if (!$defaultNickname) { $defaultNickname = "my-computer" }
    $defaultLogDir = "$env:USERPROFILE\.local\share\git-monitor"
    $defaultMaxSizeMb = 100

    if ($existingConfig) {
        Write-Host "Existing configuration detected:" -ForegroundColor $Colors.Blue
        Write-Host "  Device Nickname: $($existingConfig.DeviceNickname)" -ForegroundColor White
        Write-Host "  Log Directory: $($existingConfig.LogDir)" -ForegroundColor White
        Write-Host "  Max Log Size: $($existingConfig.MaxSizeMb)MB" -ForegroundColor White
        Write-Host ""

        $keepExisting = Read-Host "Keep the existing configuration? [Y/n]"
        if ($keepExisting -notin @("n", "N", "no", "NO", "No")) {
            return @{
                DeviceNickname = $existingConfig.DeviceNickname
                LogDir = $existingConfig.LogDir
                MaxSizeMb = $existingConfig.MaxSizeMb
                KeepExisting = $true
            }
        }

        $defaultNickname = $existingConfig.DeviceNickname
        $defaultLogDir = $existingConfig.LogDir
        $defaultMaxSizeMb = $existingConfig.MaxSizeMb
    }

    Write-Host "Device Nickname:" -ForegroundColor $Colors.Blue
    Write-Host "  This identifies your device in log entries" -ForegroundColor Gray
    $deviceNickname = Read-Host "Device nickname [$defaultNickname]"
    if ([string]::IsNullOrWhiteSpace($deviceNickname)) {
        $deviceNickname = $defaultNickname
    }

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
    $maxSizeMb = Read-Host "Maximum log file size in MB [$defaultMaxSizeMb]"
    if ([string]::IsNullOrWhiteSpace($maxSizeMb) -or !($maxSizeMb -match '^\d+$')) {
        $maxSizeMb = $defaultMaxSizeMb
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
        KeepExisting = $false
    }
}

function New-Config {
    Write-Info "Setting up configuration..."

    try {
        $config = Get-UserConfiguration
        if (!$config) {
            return $false
        }

        if ($config.KeepExisting) {
            $configPath = Join-Path $ConfigDir "config.json"
            Write-Success "Keeping existing configuration at $configPath"
            Write-Success "Log will continue to be written to: $(Join-Path $config.LogDir "$($config.DeviceNickname)_githistory.log")"
            return $true
        }

        New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        New-Item -Path $config.LogDir -ItemType Directory -Force | Out-Null

        $configPath = Join-Path $ConfigDir "config.json"
        $logFile = Join-Path $config.LogDir "$($config.DeviceNickname)_githistory.log"
        $backupPath = Backup-ExistingConfiguration -ConfigPath $configPath
        if ($backupPath) {
            Write-Success "Backed up existing configuration to $backupPath"
        }

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
        $process = Start-Process -FilePath $exePath -ArgumentList "start" -WindowStyle Hidden -PassThru
        if ($process.WaitForExit(10000)) {
            $process.Refresh()
            $exitCode = $process.ExitCode
        } else {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            } catch {}
            $exitCode = 124
        }

        if ($exitCode -eq 0) {
            Write-Success "Monitoring enabled"
            Write-Info "Automatic sign-in startup was configured for the background monitor"
            Write-Info "Open a new PowerShell or pwsh window to load the installed profile hook"
        } elseif ($exitCode -eq 124) {
            Write-Warning "Automatic activation did not complete within 10 seconds"
            Write-Info "You can enable it later with: git-monitor start"
        } else {
            Write-Warning "Automatic activation failed with exit code $exitCode"
            Write-Info "You can enable it later with: git-monitor start"
        }
    } catch {
        Write-Warning "Automatic activation failed: $($_.Exception.Message)"
        Write-Info "You can enable it later with: git-monitor start"
    }

    return $true
}

function Invoke-PostInstallSelfCheck {
    if ($NoService) {
        Write-Info "Skipping post-install self-check (--NoService specified)"
        return $true
    }

    Write-Info "Running post-install self-check..."

    try {
        $exePath = Get-ExePath
        $configPath = Join-Path $ConfigDir "config.json"
        $logPath = Get-ConfiguredLogPath

        Write-Host "  Status:" -ForegroundColor White
        & $exePath status 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }

        $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) "git-monitor-install-check-$PID"
        New-Item -Path $tempRepo -ItemType Directory -Force | Out-Null

        try {
            git init --quiet $tempRepo | Out-Null
            & $exePath capture --config $configPath --shell powershell --cwd $tempRepo --parent-pid $PID -- status 2>$null
            Start-Sleep -Milliseconds 250
        } finally {
            Remove-Item -Path $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
        }

        if ($logPath) {
            Write-Host "  Detected log path: $logPath" -ForegroundColor White
            if (Test-Path $logPath) {
                $latestEntry = Get-Content $logPath | Select-Object -Last 1
                if ($latestEntry) {
                    Write-Host "  Latest log entry: $latestEntry" -ForegroundColor White
                } else {
                    Write-Warning "Log file exists but no entries were found after self-check"
                }
            } else {
                Write-Warning "Log file was not created during self-check"
            }
        } else {
            Write-Warning "Could not determine configured log path for self-check"
        }
    } catch {
        Write-Warning "Post-install self-check failed: $($_.Exception.Message)"
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
        Write-Host "Automatic sign-in startup was configured for the background monitor." -ForegroundColor Green
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
    Write-Host "  https://github.com/Cerebellum-Lab/git-log-access"
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
    $packageExePath = [System.IO.Path]::GetFullPath((Get-ScriptAssetPath "git-monitor.exe"))
    $resolvedCommands = @()

    try {
        $resolvedCommands = @(Get-Command git-monitor -All -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Source -and ([System.IO.Path]::GetFullPath($_.Source) -ne $packageExePath)
            } |
            Select-Object -ExpandProperty Source -Unique)
        $commandAvailable = $resolvedCommands.Count -gt 0
    } catch {}

    if ((Test-Path $exePath) -or (Test-Path $configPath) -or $commandAvailable) {
        Write-Warning "Git Monitor installation detected:"
        if (Test-Path $exePath) { Write-Host "  Executable: $exePath" -ForegroundColor Yellow }
        if (Test-Path $configPath) { Write-Host "  Config: $configPath" -ForegroundColor Yellow }
        if ($commandAvailable) {
            Write-Host "  Command available in PATH" -ForegroundColor Yellow
            foreach ($resolved in $resolvedCommands) {
                Write-Host "    $resolved" -ForegroundColor Yellow
            }
        }

        if ($Force) {
            Write-Info "Force flag detected - proceeding with reinstallation..."
            return $true
        }

        if ($Silent) {
            Write-Info "Silent mode - proceeding with reinstallation..."
            $script:Force = $true
            return $true
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
    Invoke-PostInstallSelfCheck | Out-Null
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
