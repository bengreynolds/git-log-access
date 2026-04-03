use anyhow::Result;
use std::path::Path;

#[cfg(windows)]
use anyhow::Context;
#[cfg(windows)]
use std::fs;
#[cfg(windows)]
use std::path::PathBuf;
#[cfg(windows)]
use std::process::Command;

#[cfg(windows)]
const RUN_KEY_PATH: &str = r"HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";
#[cfg(windows)]
const RUN_VALUE_NAME: &str = "GitMonitor";
#[cfg(windows)]
const LAUNCHER_SCRIPT_NAME: &str = "autostart.ps1";

#[derive(Debug, Clone)]
pub struct StartupStatus {
    pub supported: bool,
    pub configured: bool,
    pub description: String,
}

pub struct StartupManager;

impl StartupManager {
    pub fn enable(config_path: &Path) -> Result<StartupStatus> {
        #[cfg(windows)]
        {
            let exe_path =
                std::env::current_exe().context("Failed to determine executable path")?;
            let launcher_path = launcher_script_path()?;
            let launcher_body = render_launcher_script(&exe_path, config_path);

            if let Some(parent) = launcher_path.parent() {
                fs::create_dir_all(parent).with_context(|| {
                    format!("Failed to create auto-start state directory: {:?}", parent)
                })?;
            }
            fs::write(&launcher_path, launcher_body).with_context(|| {
                format!(
                    "Failed to write auto-start launcher script: {:?}",
                    launcher_path
                )
            })?;

            let run_command = render_run_command(&launcher_path);
            let script = format!(
                "$path = {}; $name = {}; $value = {}; New-Item -Path $path -Force | Out-Null; Set-ItemProperty -Path $path -Name $name -Value $value",
                powershell_quote_str(RUN_KEY_PATH),
                powershell_quote_str(RUN_VALUE_NAME),
                powershell_quote_str(&run_command)
            );
            let output = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    &script,
                ])
                .output()
                .context("Failed to register Windows Run entry for Git Monitor")?;

            if !output.status.success() {
                anyhow::bail!(
                    "Failed to register Windows Run entry: {}",
                    String::from_utf8_lossy(&output.stderr).trim()
                );
            }

            Self::status()
        }

        #[cfg(not(windows))]
        {
            let _ = config_path;
            Ok(StartupStatus {
                supported: false,
                configured: false,
                description: "unsupported".to_string(),
            })
        }
    }

    pub fn disable() -> Result<()> {
        #[cfg(windows)]
        {
            let script = format!(
                "$path = {}; $name = {}; Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue",
                powershell_quote_str(RUN_KEY_PATH),
                powershell_quote_str(RUN_VALUE_NAME)
            );
            let output = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    &script,
                ])
                .output()
                .context("Failed to remove Windows Run entry for Git Monitor")?;

            if !output.status.success() {
                anyhow::bail!(
                    "Failed to remove Windows Run entry: {}",
                    String::from_utf8_lossy(&output.stderr).trim()
                );
            }

            let launcher_path = launcher_script_path()?;
            if launcher_path.exists() {
                fs::remove_file(&launcher_path).with_context(|| {
                    format!(
                        "Failed to remove auto-start launcher script: {:?}",
                        launcher_path
                    )
                })?;
            }

            Ok(())
        }

        #[cfg(not(windows))]
        {
            Ok(())
        }
    }

    pub fn status() -> Result<StartupStatus> {
        #[cfg(windows)]
        {
            let script = format!(
                "$path = {}; $name = {}; try {{ $item = Get-ItemProperty -Path $path -ErrorAction Stop; $value = $item.PSObject.Properties[$name].Value; if ($null -ne $value) {{ Write-Output $value }} }} catch {{}}",
                powershell_quote_str(RUN_KEY_PATH),
                powershell_quote_str(RUN_VALUE_NAME)
            );
            let output = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-Command",
                    &script,
                ])
                .output()
                .context("Failed to query Windows Run entry for Git Monitor")?;

            if !output.status.success() {
                anyhow::bail!(
                    "Failed to query Windows Run entry: {}",
                    String::from_utf8_lossy(&output.stderr).trim()
                );
            }

            let value = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if value.is_empty() {
                return Ok(StartupStatus {
                    supported: true,
                    configured: false,
                    description: format!("Run entry `{RUN_VALUE_NAME}` not registered"),
                });
            }

            let launcher_path = launcher_script_path()?;
            let launcher_status = if launcher_path.exists() {
                "launcher present"
            } else {
                "launcher missing"
            };

            Ok(StartupStatus {
                supported: true,
                configured: true,
                description: format!("HKCU Run entry `{RUN_VALUE_NAME}` ({launcher_status})"),
            })
        }

        #[cfg(not(windows))]
        {
            Ok(StartupStatus {
                supported: false,
                configured: false,
                description: "unsupported".to_string(),
            })
        }
    }
}

#[cfg(windows)]
fn launcher_script_path() -> Result<PathBuf> {
    Ok(crate::config::Config::default_state_dir()?.join(LAUNCHER_SCRIPT_NAME))
}

#[cfg(windows)]
fn render_run_command(launcher_path: &Path) -> String {
    format!(
        "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File {}",
        windows_quote_arg(launcher_path)
    )
}

#[cfg(windows)]
fn render_launcher_script(exe_path: &Path, config_path: &Path) -> String {
    format!(
        "$exePath = {}\n\
$configPath = {}\n\
$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |\n\
    Where-Object {{ $_.Name -eq 'git-monitor.exe' -and $_.CommandLine -like '*daemon*' }} |\n\
    Select-Object -First 1\n\
if (-not $existing) {{\n\
    Start-Process -FilePath $exePath -ArgumentList @('daemon', '--config', $configPath) -WindowStyle Hidden\n\
}}\n",
        powershell_quote(exe_path),
        powershell_quote(config_path)
    )
}

#[cfg(windows)]
fn windows_quote_arg(path: &Path) -> String {
    format!("\"{}\"", path.to_string_lossy().replace('"', "\"\""))
}

#[cfg(windows)]
fn powershell_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "''"))
}

#[cfg(windows)]
fn powershell_quote_str(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

#[cfg(test)]
mod tests {
    #[cfg(windows)]
    use super::*;
    #[cfg(windows)]
    use std::path::PathBuf;

    #[cfg(windows)]
    #[test]
    fn test_render_run_command_quotes_launcher_path() {
        let path = PathBuf::from(r"C:\Users\name\AppData\Roaming\git-monitor\autostart.ps1");
        let command = render_run_command(&path);
        assert!(command.contains(r#""C:\Users\name\AppData\Roaming\git-monitor\autostart.ps1""#));
    }

    #[cfg(windows)]
    #[test]
    fn test_render_launcher_script_references_daemon_mode() {
        let exe = PathBuf::from(r"C:\Program Files\Git Monitor\git-monitor.exe");
        let config = PathBuf::from(r"C:\Users\name\AppData\Roaming\git-monitor\config.json");
        let script = render_launcher_script(&exe, &config);
        assert!(script.contains("Start-Process -FilePath $exePath"));
        assert!(script.contains("@('daemon', '--config', $configPath)"));
        assert!(script.contains("git-monitor.exe"));
    }
}
