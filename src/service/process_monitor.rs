use crate::monitor::{extract_git_command, is_git_command, ParsedGitCommand};
use crate::service::{daemon::GitMonitorDaemon, CommandHintStore};
use crate::utils::{format_timestamp, normalize_path, resolve_path_context};
use anyhow::{Context, Result};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use tokio::time::{sleep, Duration};

const UNKNOWN_ROOT: &str = "<unknown>";

#[derive(Debug, Clone)]
struct ObservedProcess {
    pid: u32,
    parent_pid: Option<u32>,
    command_line: String,
    working_dir: Option<PathBuf>,
    shell_context: String,
}

pub struct ProcessMonitor {
    seen: HashMap<u32, String>,
    poll_interval: Duration,
}

impl ProcessMonitor {
    pub fn new() -> Self {
        Self {
            seen: HashMap::new(),
            poll_interval: Duration::from_secs(1),
        }
    }

    pub async fn run(&mut self, daemon: &GitMonitorDaemon) -> Result<()> {
        loop {
            self.poll_once(daemon).await?;
            sleep(self.poll_interval).await;
        }
    }

    pub async fn poll_once(&mut self, daemon: &GitMonitorDaemon) -> Result<()> {
        let processes = list_git_processes()?;
        let current_pids: HashSet<u32> = processes.iter().map(|process| process.pid).collect();
        self.seen.retain(|pid, _| current_pids.contains(pid));

        for mut process in processes {
            let should_log = self
                .seen
                .get(&process.pid)
                .map(|command| command != &process.command_line)
                .unwrap_or(true);

            if should_log {
                if let Some(hint) =
                    CommandHintStore::consume_recent(&process.command_line, process.parent_pid)?
                {
                    if process.working_dir.is_none() {
                        process.working_dir = hint.working_dir_path();
                    }
                    if hint.logged_by_hook {
                        self.seen.insert(process.pid, process.command_line);
                        continue;
                    }
                }

                daemon
                    .log_observed_process(
                        &process.command_line,
                        process.working_dir,
                        Some(process.shell_context),
                    )
                    .await?;
                self.seen.insert(process.pid, process.command_line);
            }
        }

        Ok(())
    }
}

#[cfg(windows)]
fn list_git_processes() -> Result<Vec<ObservedProcess>> {
    let command = "$procs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^git(\\.exe)?$' -or ($_.CommandLine -match '(^|\\\\s)(git|git\\\\.exe)(\\\\s|$)') }; if ($procs) { $procs | Select-Object ProcessId, ParentProcessId, CommandLine, ExecutablePath | ConvertTo-Json -Compress }";
    let output = std::process::Command::new("powershell")
        .args(["-NoProfile", "-Command", command])
        .output()
        .context("Failed to query Windows process table")?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if stdout.is_empty() {
        return Ok(Vec::new());
    }

    let rows = deserialize_windows_processes(&stdout)?;
    Ok(rows
        .into_iter()
        .filter_map(|row| {
            let command_line = row.command_line?;
            if !is_git_command(&command_line) {
                return None;
            }

            let working_dir = infer_working_dir_from_command(&command_line, None);
            Some(ObservedProcess {
                pid: row.process_id,
                parent_pid: row.parent_process_id,
                command_line,
                working_dir,
                shell_context: "process:windows".to_string(),
            })
        })
        .collect())
}

#[cfg(unix)]
fn list_git_processes() -> Result<Vec<ObservedProcess>> {
    let mut processes = Vec::new();

    let proc_dir = PathBuf::from("/proc");
    if proc_dir.exists() {
        for entry in std::fs::read_dir(proc_dir).context("Failed to read /proc")? {
            let entry = entry?;
            let pid = match entry.file_name().to_string_lossy().parse::<u32>() {
                Ok(pid) => pid,
                Err(_) => continue,
            };
            let process_dir = entry.path();
            let cmdline_path = process_dir.join("cmdline");
            let raw = match std::fs::read(&cmdline_path) {
                Ok(raw) if !raw.is_empty() => raw,
                _ => continue,
            };
            let parts: Vec<String> = raw
                .split(|byte| *byte == 0)
                .filter(|part| !part.is_empty())
                .map(|part| String::from_utf8_lossy(part).to_string())
                .collect();
            if parts.is_empty() {
                continue;
            }

            let command_line = parts.join(" ");
            if !is_git_command(&command_line) {
                continue;
            }

            let working_dir = std::fs::read_link(process_dir.join("cwd")).ok();
            processes.push(ObservedProcess {
                pid,
                parent_pid: None,
                command_line,
                working_dir,
                shell_context: "process:unix".to_string(),
            });
        }
    }

    Ok(processes)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct WindowsProcessRow {
    process_id: u32,
    parent_process_id: Option<u32>,
    command_line: Option<String>,
}

#[cfg(windows)]
fn deserialize_windows_processes(json: &str) -> Result<Vec<WindowsProcessRow>> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Rows {
        One(WindowsProcessRow),
        Many(Vec<WindowsProcessRow>),
    }

    let rows = serde_json::from_str::<Rows>(json)
        .with_context(|| format!("Failed to parse Windows process list: {json}"))?;

    Ok(match rows {
        Rows::One(row) => vec![row],
        Rows::Many(rows) => rows,
    })
}

impl GitMonitorDaemon {
    pub async fn log_observed_process(
        &self,
        command_line: &str,
        working_dir: Option<PathBuf>,
        shell_context: Option<String>,
    ) -> Result<()> {
        let fallback_root = infer_root_dir(command_line, working_dir.as_ref());

        if let Some(work_dir) = working_dir {
            return self
                .process_git_command_with_context(command_line, Some(work_dir), shell_context)
                .await;
        }

        if !is_git_command(command_line) {
            return Ok(());
        }

        let parser = self.parser.read().await;
        let command = match extract_git_command(command_line) {
            Some(command) => command,
            None => return Ok(()),
        };

        if !crate::monitor::should_log_command(&command, parser.filters()) {
            return Ok(());
        }

        let parsed = ParsedGitCommand {
            timestamp: format_timestamp(),
            root_dir: fallback_root.unwrap_or_else(|| UNKNOWN_ROOT.to_string()),
            command,
            working_dir: None,
            shell_context,
        };

        self.logger.log_command(parsed).await?;
        self.logger.flush().await?;
        Ok(())
    }
}

fn infer_root_dir(command_line: &str, working_dir: Option<&PathBuf>) -> Option<String> {
    if let Some(dir) = working_dir {
        return normalize_path(dir).ok();
    }

    infer_working_dir_from_command(command_line, None).and_then(|dir| normalize_path(dir).ok())
}

fn infer_working_dir_from_command(
    command_line: &str,
    base_dir: Option<&PathBuf>,
) -> Option<PathBuf> {
    let parts: Vec<&str> = command_line.split_whitespace().collect();
    let mut index = 0;
    while index < parts.len() {
        if parts[index] == "-C" {
            let path = parts.get(index + 1)?;
            let trimmed = path.trim_matches('"').trim_matches('\'');
            return match base_dir {
                Some(base) => resolve_path_context(trimmed, Some(base)).ok(),
                None => Some(PathBuf::from(trimmed)),
            };
        }
        index += 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_infer_working_dir_from_command() {
        let dir = infer_working_dir_from_command("git -C repo status", None).unwrap();
        assert_eq!(dir, PathBuf::from("repo"));
    }

    #[cfg(windows)]
    #[test]
    fn test_deserialize_windows_processes_accepts_single_object() {
        let rows = deserialize_windows_processes(
            r#"{"ProcessId":123,"CommandLine":"git status","ExecutablePath":"C:\\Git\\bin\\git.exe"}"#,
        )
        .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].process_id, 123);
    }
}
