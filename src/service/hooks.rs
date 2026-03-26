use crate::config::Config;
use anyhow::{Context, Result};
use std::fs;
use std::path::{Path, PathBuf};

const MARKER_START: &str = "# >>> git-monitor hook >>>";
const MARKER_END: &str = "# <<< git-monitor hook <<<";
const ENABLED_FILE: &str = "enabled.flag";

#[derive(Debug, Clone)]
pub struct HookTarget {
    pub shell: String,
    pub path: PathBuf,
    pub supported: bool,
    pub installed: bool,
}

#[derive(Debug, Clone)]
pub struct HookStatus {
    pub enabled: bool,
    pub targets: Vec<HookTarget>,
}

pub struct HookManager;

impl HookManager {
    pub fn install(config: &Config) -> Result<HookStatus> {
        let exe_path = std::env::current_exe().context("Failed to determine git-monitor path")?;
        let targets = Self::target_paths(config)?;

        for target in &targets {
            if !target.supported {
                continue;
            }

            let hook_body = render_hook(&target.shell, &exe_path)?;
            ensure_hook_block(&target.path, &hook_body)?;
        }

        Self::set_enabled(config, true)?;
        Self::status(config)
    }

    pub fn uninstall(config: &Config) -> Result<HookStatus> {
        let targets = Self::target_paths(config)?;

        for target in &targets {
            if !target.supported || !target.path.exists() {
                continue;
            }

            remove_hook_block(&target.path)?;
        }

        Self::set_enabled(config, false)?;
        Self::status(config)
    }

    pub fn set_enabled(_config: &Config, enabled: bool) -> Result<()> {
        let state_dir = Config::default_state_dir()?;
        fs::create_dir_all(&state_dir)
            .with_context(|| format!("Failed to create state directory: {:?}", state_dir))?;

        let enabled_path = state_dir.join(ENABLED_FILE);
        if enabled {
            fs::write(&enabled_path, b"enabled")
                .with_context(|| format!("Failed to write enabled flag: {:?}", enabled_path))?;
        } else if enabled_path.exists() {
            fs::remove_file(&enabled_path)
                .with_context(|| format!("Failed to remove enabled flag: {:?}", enabled_path))?;
        }

        Ok(())
    }

    pub fn is_enabled() -> Result<bool> {
        Ok(Config::default_state_dir()?.join(ENABLED_FILE).exists())
    }

    pub fn status(config: &Config) -> Result<HookStatus> {
        let targets = Self::target_paths(config)?
            .into_iter()
            .map(|mut target| {
                target.installed =
                    target.supported && hook_block_present(&target.path).unwrap_or(false);
                target
            })
            .collect();

        Ok(HookStatus {
            enabled: Self::is_enabled()?,
            targets,
        })
    }

    fn target_paths(config: &Config) -> Result<Vec<HookTarget>> {
        let mut targets = Vec::new();

        for shell in &config.enabled_shells {
            match shell.as_str() {
                "powershell" => {
                    if let Some(path) = powershell_profile_path("WindowsPowerShell")? {
                        targets.push(HookTarget {
                            shell: shell.clone(),
                            path,
                            supported: true,
                            installed: false,
                        });
                    }
                }
                "pwsh" => {
                    if let Some(path) = powershell_profile_path("PowerShell")? {
                        targets.push(HookTarget {
                            shell: shell.clone(),
                            path,
                            supported: true,
                            installed: false,
                        });
                    }
                }
                "bash" => targets.push(HookTarget {
                    shell: shell.clone(),
                    path: home_dir()?.join(".bashrc"),
                    supported: true,
                    installed: false,
                }),
                "zsh" => targets.push(HookTarget {
                    shell: shell.clone(),
                    path: home_dir()?.join(".zshrc"),
                    supported: true,
                    installed: false,
                }),
                "sh" => targets.push(HookTarget {
                    shell: shell.clone(),
                    path: home_dir()?.join(".profile"),
                    supported: true,
                    installed: false,
                }),
                "fish" => targets.push(HookTarget {
                    shell: shell.clone(),
                    path: home_dir()?.join(".config").join("fish").join("config.fish"),
                    supported: true,
                    installed: false,
                }),
                other => targets.push(HookTarget {
                    shell: other.to_string(),
                    path: PathBuf::from(format!("<unsupported:{other}>")),
                    supported: false,
                    installed: false,
                }),
            }
        }

        Ok(targets)
    }
}

fn ensure_hook_block(path: &Path, block: &str) -> Result<()> {
    let existing = fs::read_to_string(path).unwrap_or_default();
    let updated = upsert_hook_block(&existing, block);

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create shell profile directory: {:?}", parent))?;
    }

    fs::write(path, updated).with_context(|| format!("Failed to write hook file: {:?}", path))?;
    Ok(())
}

fn remove_hook_block(path: &Path) -> Result<()> {
    let existing = fs::read_to_string(path).unwrap_or_default();
    let updated = strip_hook_block(&existing);
    fs::write(path, updated).with_context(|| format!("Failed to write hook file: {:?}", path))?;
    Ok(())
}

fn hook_block_present(path: &Path) -> Result<bool> {
    let existing =
        fs::read_to_string(path).with_context(|| format!("Failed to read {:?}", path))?;
    Ok(existing.contains(MARKER_START) && existing.contains(MARKER_END))
}

fn upsert_hook_block(existing: &str, block: &str) -> String {
    let stripped = strip_hook_block(existing);
    let mut updated = stripped.trim_end().to_string();
    if !updated.is_empty() {
        updated.push('\n');
        updated.push('\n');
    }
    updated.push_str(MARKER_START);
    updated.push('\n');
    updated.push_str(block.trim_end());
    updated.push('\n');
    updated.push_str(MARKER_END);
    updated.push('\n');
    updated
}

fn strip_hook_block(existing: &str) -> String {
    if let (Some(start), Some(end)) = (existing.find(MARKER_START), existing.find(MARKER_END)) {
        let mut updated = String::new();
        updated.push_str(existing[..start].trim_end());
        if !updated.is_empty() {
            updated.push('\n');
        }
        updated.push_str(existing[end + MARKER_END.len()..].trim_start());
        updated
    } else {
        existing.to_string()
    }
}

fn render_hook(shell: &str, exe_path: &Path) -> Result<String> {
    let exe = shell_escape_path(shell, exe_path);

    let hook = match shell {
        "powershell" | "pwsh" => format!(
            "function global:git {{\n    & {exe} capture --shell {shell} --cwd $PWD.Path -- @args *> $null\n    $gitApp = @(Get-Command git -All | Where-Object {{ $_.CommandType -eq 'Application' }}) | Select-Object -First 1\n    if (-not $gitApp) {{ throw 'git executable not found in PATH' }}\n    & $gitApp.Source @args\n}}"
        ),
        "bash" | "zsh" | "sh" => format!(
            "git() {{\n  {exe} capture --shell {shell} --cwd \"$PWD\" -- \"$@\" >/dev/null 2>&1 || true\n  command git \"$@\"\n}}"
        ),
        "fish" => format!(
            "function git\n    {exe} capture --shell fish --cwd \"$PWD\" -- $argv >/dev/null 2>&1; or true\n    command git $argv\nend"
        ),
        other => anyhow::bail!("Unsupported shell hook: {other}"),
    };

    Ok(hook)
}

fn shell_escape_path(shell: &str, path: &Path) -> String {
    let raw = path.to_string_lossy();
    match shell {
        "powershell" | "pwsh" => format!("'{}'", raw.replace('\'', "''")),
        _ => format!("'{}'", raw.replace('\'', "'\"'\"'")),
    }
}

fn home_dir() -> Result<PathBuf> {
    #[cfg(windows)]
    {
        std::env::var("USERPROFILE")
            .map(PathBuf::from)
            .context("Could not determine home directory")
    }
    #[cfg(unix)]
    {
        std::env::var("HOME")
            .map(PathBuf::from)
            .context("Could not determine home directory")
    }
}

#[cfg(windows)]
fn powershell_profile_path(folder: &str) -> Result<Option<PathBuf>> {
    Ok(Some(
        home_dir()?
            .join("Documents")
            .join(folder)
            .join("Microsoft.PowerShell_profile.ps1"),
    ))
}

#[cfg(not(windows))]
fn powershell_profile_path(_folder: &str) -> Result<Option<PathBuf>> {
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_upsert_hook_block_replaces_existing_block() {
        let initial =
            "prefix\n# >>> git-monitor hook >>>\nold\n# <<< git-monitor hook <<<\nsuffix\n";
        let updated = upsert_hook_block(initial, "new");
        assert!(updated.contains("new"));
        assert!(!updated.contains("old"));
        assert_eq!(updated.matches(MARKER_START).count(), 1);
    }

    #[test]
    fn test_strip_hook_block_removes_marked_content() {
        let initial =
            "prefix\n# >>> git-monitor hook >>>\nbody\n# <<< git-monitor hook <<<\nsuffix\n";
        let updated = strip_hook_block(initial);
        assert!(!updated.contains("body"));
        assert!(updated.contains("prefix"));
        assert!(updated.contains("suffix"));
    }
}
