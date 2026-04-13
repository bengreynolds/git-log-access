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

const RUN_KEY_PATH_REG: &str = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run";
#[cfg(windows)]
const RUN_VALUE_NAME: &str = "GitMonitor";
#[cfg(windows)]
const LEGACY_LAUNCHER_SCRIPT_NAME: &str = "autostart.ps1";

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

            let run_command = render_run_command(&exe_path, config_path);
            write_run_entry(&run_command)?;
            cleanup_legacy_launcher_script()?;

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
            remove_run_entry()?;
            cleanup_legacy_launcher_script()?;

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
            let value = query_run_entry()?;
            if value.is_none() {
                return Ok(StartupStatus {
                    supported: true,
                    configured: false,
                    description: format!("Run entry `{RUN_VALUE_NAME}` not registered"),
                });
            }

            Ok(StartupStatus {
                supported: true,
                configured: true,
                description: format!("HKCU Run entry `{RUN_VALUE_NAME}` configured"),
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
    Ok(crate::config::Config::default_state_dir()?.join(LEGACY_LAUNCHER_SCRIPT_NAME))
}

#[cfg(windows)]
fn render_run_command(exe_path: &Path, config_path: &Path) -> String {
    format!(
        "powershell.exe -NoProfile -WindowStyle Hidden -Command \"& {} daemon --config {}\"",
        powershell_quote(exe_path),
        powershell_quote(config_path)
    )
}

#[cfg(windows)]
fn write_run_entry(run_command: &str) -> Result<()> {
    let output = Command::new("reg")
        .args([
            "add",
            RUN_KEY_PATH_REG,
            "/v",
            RUN_VALUE_NAME,
            "/t",
            "REG_SZ",
            "/d",
            run_command,
            "/f",
        ])
        .output()
        .context("Failed to register Windows Run entry for Git Monitor")?;

    if !output.status.success() {
        anyhow::bail!(
            "Failed to register Windows Run entry: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }

    Ok(())
}

#[cfg(windows)]
fn remove_run_entry() -> Result<()> {
    let output = Command::new("reg")
        .args(["delete", RUN_KEY_PATH_REG, "/v", RUN_VALUE_NAME, "/f"])
        .output()
        .context("Failed to remove Windows Run entry for Git Monitor")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.contains("unable to find the specified registry value or key")
            && !stderr.contains("was unable to find the specified registry value or key")
        {
            anyhow::bail!(
                "Failed to remove Windows Run entry: {}",
                stderr.trim()
            );
        }
    }

    Ok(())
}

#[cfg(windows)]
fn query_run_entry() -> Result<Option<String>> {
    let output = Command::new("reg")
        .args(["query", RUN_KEY_PATH_REG, "/v", RUN_VALUE_NAME])
        .output()
        .context("Failed to query Windows Run entry for Git Monitor")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stderr.contains("unable to find the specified registry value or key")
            || stderr.contains("was unable to find the specified registry value or key")
        {
            return Ok(None);
        }

        anyhow::bail!("Failed to query Windows Run entry: {}", stderr.trim());
    }

    Ok(parse_reg_value(&output.stdout))
}

#[cfg(windows)]
fn parse_reg_value(output: &[u8]) -> Option<String> {
    for line in String::from_utf8_lossy(output).lines() {
        let trimmed = line.trim();
        let mut parts = trimmed.split_whitespace();
        if let (Some(name), Some(kind)) = (parts.next(), parts.next()) {
            if name.eq_ignore_ascii_case(RUN_VALUE_NAME) && kind.eq_ignore_ascii_case("REG_SZ") {
                let value = parts.collect::<Vec<_>>().join(" ");
                if !value.is_empty() {
                    return Some(value);
                }
            }
        }
    }

    None
}

#[cfg(windows)]
fn cleanup_legacy_launcher_script() -> Result<()> {
    let launcher_path = launcher_script_path()?;
    if launcher_path.exists() {
        fs::remove_file(&launcher_path).with_context(|| {
            format!(
                "Failed to remove legacy auto-start launcher script: {:?}",
                launcher_path
            )
        })?;
    }

    Ok(())
}

#[cfg(windows)]
fn powershell_quote(path: &Path) -> String {
    format!("'{}'", path.to_string_lossy().replace('\'', "''"))
}
