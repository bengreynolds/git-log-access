use crate::config::Config;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const HINTS_DIR: &str = "command-hints";
const MAX_HINT_AGE_MS: i64 = 15_000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CommandHint {
    pub recorded_at_ms: i64,
    pub parent_pid: Option<u32>,
    pub command_signature: String,
    pub working_dir: Option<String>,
    pub shell_context: Option<String>,
    pub logged_by_hook: bool,
}

impl CommandHint {
    pub fn working_dir_path(&self) -> Option<PathBuf> {
        self.working_dir.as_ref().map(PathBuf::from)
    }
}

pub struct CommandHintStore;

impl CommandHintStore {
    pub fn record_hook_command(
        command_line: &str,
        working_dir: Option<&Path>,
        shell_context: Option<&str>,
        parent_pid: Option<u32>,
    ) -> Result<()> {
        let hints_dir = hints_dir()?;
        fs::create_dir_all(&hints_dir)
            .with_context(|| format!("Failed to create hint directory: {:?}", hints_dir))?;

        let now_ms = now_timestamp_ms()?;
        prune_stale_hints(&hints_dir, now_ms)?;

        let signature = match normalize_command_signature(command_line) {
            Some(signature) => signature,
            None => return Ok(()),
        };

        let hint = CommandHint {
            recorded_at_ms: now_ms,
            parent_pid,
            command_signature: signature,
            working_dir: working_dir.map(|path| path.to_string_lossy().to_string()),
            shell_context: shell_context.map(str::to_string),
            logged_by_hook: true,
        };

        write_hint(&hints_dir, &hint)
    }

    pub fn consume_recent(
        command_line: &str,
        parent_pid: Option<u32>,
    ) -> Result<Option<CommandHint>> {
        let hints_dir = hints_dir()?;
        if !hints_dir.exists() {
            return Ok(None);
        }

        let now_ms = now_timestamp_ms()?;
        prune_stale_hints(&hints_dir, now_ms)?;

        let signature = match normalize_command_signature(command_line) {
            Some(signature) => signature,
            None => return Ok(None),
        };

        consume_hint(&hints_dir, &signature, parent_pid, now_ms)
    }
}

fn hints_dir() -> Result<PathBuf> {
    Ok(Config::default_state_dir()?.join(HINTS_DIR))
}

fn write_hint(hints_dir: &Path, hint: &CommandHint) -> Result<()> {
    let payload = serde_json::to_vec(hint).context("Failed to serialize command hint")?;

    for attempt in 0..10 {
        let candidate = hints_dir.join(format!(
            "{}-{}-{}.json",
            hint.recorded_at_ms,
            std::process::id(),
            attempt
        ));

        match fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&candidate)
        {
            Ok(mut file) => {
                use std::io::Write;
                file.write_all(&payload)
                    .with_context(|| format!("Failed to write command hint: {:?}", candidate))?;
                return Ok(());
            }
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(err) => {
                return Err(err)
                    .with_context(|| format!("Failed to create command hint: {:?}", candidate));
            }
        }
    }

    anyhow::bail!(
        "Failed to allocate unique command hint file in {:?}",
        hints_dir
    );
}

fn consume_hint(
    hints_dir: &Path,
    signature: &str,
    parent_pid: Option<u32>,
    now_ms: i64,
) -> Result<Option<CommandHint>> {
    let mut candidates = Vec::new();

    for entry in
        fs::read_dir(hints_dir).with_context(|| format!("Failed to read {:?}", hints_dir))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let hint = match read_hint(&path) {
            Ok(hint) => hint,
            Err(_) => {
                let _ = fs::remove_file(&path);
                continue;
            }
        };

        if !is_recent(&hint, now_ms) || hint.command_signature != signature {
            continue;
        }

        let exact_parent = parent_pid.is_some() && hint.parent_pid == parent_pid;
        let parent_score = if exact_parent {
            2
        } else if hint.parent_pid.is_none() {
            1
        } else {
            0
        };
        candidates.push((parent_score, hint.recorded_at_ms, path, hint));
    }

    candidates.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| right.1.cmp(&left.1)));

    if let Some((_, _, path, hint)) = candidates.into_iter().next() {
        fs::remove_file(&path)
            .with_context(|| format!("Failed to remove consumed hint: {:?}", path))?;
        return Ok(Some(hint));
    }

    Ok(None)
}

fn read_hint(path: &Path) -> Result<CommandHint> {
    let payload = fs::read(path).with_context(|| format!("Failed to read hint: {:?}", path))?;
    serde_json::from_slice(&payload).with_context(|| format!("Failed to parse hint: {:?}", path))
}

fn prune_stale_hints(hints_dir: &Path, now_ms: i64) -> Result<()> {
    if !hints_dir.exists() {
        return Ok(());
    }

    for entry in
        fs::read_dir(hints_dir).with_context(|| format!("Failed to read {:?}", hints_dir))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        match read_hint(&path) {
            Ok(hint) if is_recent(&hint, now_ms) => {}
            _ => {
                let _ = fs::remove_file(&path);
            }
        }
    }

    Ok(())
}

fn is_recent(hint: &CommandHint, now_ms: i64) -> bool {
    hint.recorded_at_ms <= now_ms && now_ms - hint.recorded_at_ms <= MAX_HINT_AGE_MS
}

fn now_timestamp_ms() -> Result<i64> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("System clock is before UNIX_EPOCH")?;
    Ok(now.as_millis() as i64)
}

fn normalize_command_signature(command_line: &str) -> Option<String> {
    let tokens = tokenize_command_line(command_line);
    if tokens.is_empty() {
        return None;
    }

    let git_index = tokens.iter().position(|token| is_git_executable(token))?;
    let mut normalized = vec!["git".to_string()];
    normalized.extend(tokens[git_index + 1..].iter().cloned());
    Some(render_tokens(&normalized))
}

fn tokenize_command_line(command_line: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;

    for ch in command_line.chars() {
        match quote {
            Some(active) if ch == active => quote = None,
            Some(_) => current.push(ch),
            None if ch == '"' || ch == '\'' => quote = Some(ch),
            None if ch.is_whitespace() => {
                if !current.is_empty() {
                    tokens.push(std::mem::take(&mut current));
                }
            }
            None => current.push(ch),
        }
    }

    if !current.is_empty() {
        tokens.push(current);
    }

    tokens
}

fn is_git_executable(token: &str) -> bool {
    let normalized = token
        .trim()
        .trim_matches('"')
        .trim_matches('\'')
        .replace('\\', "/");
    let lowered = normalized.to_ascii_lowercase();
    lowered == "git"
        || lowered == "git.exe"
        || lowered.ends_with("/git")
        || lowered.ends_with("/git.exe")
}

fn render_tokens(tokens: &[String]) -> String {
    tokens
        .iter()
        .map(|token| {
            if token.contains(char::is_whitespace) || token.contains('"') {
                format!("\"{}\"", token.replace('"', "\\\""))
            } else {
                token.clone()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_normalize_command_signature_strips_git_path() {
        let signature =
            normalize_command_signature("\"C:\\Program Files\\Git\\bin\\git.exe\" status").unwrap();
        assert_eq!(signature, "git status");
    }

    #[test]
    fn test_normalize_command_signature_preserves_quoted_args() {
        let signature = normalize_command_signature("git commit -m \"hello world\"").unwrap();
        assert_eq!(signature, "git commit -m \"hello world\"");
    }

    #[test]
    fn test_consume_hint_prefers_parent_pid_match() {
        let temp_dir = TempDir::new().unwrap();
        let now_ms = now_timestamp_ms().unwrap();
        let first = CommandHint {
            recorded_at_ms: now_ms,
            parent_pid: Some(11),
            command_signature: "git status".to_string(),
            working_dir: Some("repo-a".to_string()),
            shell_context: Some("powershell".to_string()),
            logged_by_hook: true,
        };
        let second = CommandHint {
            recorded_at_ms: now_ms + 1,
            parent_pid: Some(22),
            command_signature: "git status".to_string(),
            working_dir: Some("repo-b".to_string()),
            shell_context: Some("pwsh".to_string()),
            logged_by_hook: true,
        };

        write_hint(temp_dir.path(), &first).unwrap();
        write_hint(temp_dir.path(), &second).unwrap();

        let matched = consume_hint(temp_dir.path(), "git status", Some(11), now_ms + 2)
            .unwrap()
            .unwrap();
        assert_eq!(matched.working_dir.as_deref(), Some("repo-a"));
    }
}
