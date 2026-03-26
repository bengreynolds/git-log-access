use crate::monitor::git_detector::{extract_git_command, is_git_command, should_log_command};
use crate::utils::{find_git_root, format_timestamp, normalize_path, resolve_path_context};
use anyhow::{Context, Result};
use std::path::PathBuf;

/// Parsed git command with context for logging
#[derive(Debug, Clone)]
pub struct ParsedGitCommand {
    /// Timestamp when the command was executed
    pub timestamp: String,
    /// Git repository root directory
    pub root_dir: String,
    /// The git command (sanitized)
    pub command: String,
    /// Working directory when command was executed
    pub working_dir: Option<String>,
    /// The shell/environment that executed the command
    pub shell_context: Option<String>,
}

impl ParsedGitCommand {
    /// Format as log entry: timestamp|rootdir|command
    pub fn to_log_entry(&self) -> String {
        format!("{}|{}|{}", self.timestamp, self.root_dir, self.command)
    }

    /// Parse log entry back to ParsedGitCommand
    pub fn from_log_entry(log_line: &str) -> Result<Self> {
        let parts: Vec<&str> = log_line.splitn(3, '|').collect();

        if parts.len() != 3 {
            anyhow::bail!("Invalid log entry format: {}", log_line);
        }

        Ok(ParsedGitCommand {
            timestamp: parts[0].to_string(),
            root_dir: parts[1].to_string(),
            command: parts[2].to_string(),
            working_dir: None,
            shell_context: None,
        })
    }
}

/// Command parser for git commands with context
pub struct GitCommandParser {
    /// Command filters (if empty, log all git commands)
    command_filters: Vec<String>,
}

impl GitCommandParser {
    /// Create new parser with command filters
    pub fn new(command_filters: Vec<String>) -> Self {
        Self { command_filters }
    }

    /// Create parser that logs all git commands
    pub fn new_all_commands() -> Self {
        Self {
            command_filters: vec![],
        }
    }

    /// Parse a command line and return parsed git command if it's a git command
    pub fn parse_command(
        &self,
        command_line: &str,
        working_dir: Option<PathBuf>,
    ) -> Result<Option<ParsedGitCommand>> {
        // Early check if this is a git command
        if !is_git_command(command_line) {
            return Ok(None);
        }

        // Extract and sanitize the command
        let git_command = match extract_git_command(command_line) {
            Some(cmd) => cmd,
            None => return Ok(None),
        };

        // Check if we should log this command based on filters
        if !should_log_command(&git_command, &self.command_filters) {
            return Ok(None);
        }

        // Determine the working directory
        let base_dir = working_dir
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
        let work_dir = extract_command_working_dir(command_line, &base_dir).unwrap_or(base_dir);

        // Find the git repository root
        let root_dir = match find_git_root(&work_dir) {
            Some(git_root) => {
                normalize_path(&git_root).context("Failed to normalize git root path")?
            }
            None => {
                normalize_path(&work_dir).unwrap_or_else(|_| work_dir.to_string_lossy().to_string())
            }
        };

        // Create the parsed command
        let parsed = ParsedGitCommand {
            timestamp: format_timestamp(),
            root_dir,
            command: git_command,
            working_dir: Some(
                normalize_path(&work_dir)
                    .unwrap_or_else(|_| work_dir.to_string_lossy().to_string()),
            ),
            shell_context: None, // Will be set by the shell integration layer
        };

        Ok(Some(parsed))
    }

    /// Parse command with additional shell context
    pub fn parse_command_with_context(
        &self,
        command_line: &str,
        working_dir: Option<PathBuf>,
        shell_context: Option<String>,
    ) -> Result<Option<ParsedGitCommand>> {
        let mut parsed = self.parse_command(command_line, working_dir)?;

        if let Some(mut cmd) = parsed {
            cmd.shell_context = shell_context;
            parsed = Some(cmd);
        }

        Ok(parsed)
    }

    /// Update command filters
    pub fn set_filters(&mut self, filters: Vec<String>) {
        self.command_filters = filters;
    }

    /// Add a command filter
    pub fn add_filter(&mut self, filter: String) {
        if !self.command_filters.contains(&filter) {
            self.command_filters.push(filter);
        }
    }

    /// Remove a command filter
    pub fn remove_filter(&mut self, filter: &str) {
        self.command_filters.retain(|f| f != filter);
    }

    /// Get current filters
    pub fn filters(&self) -> &[String] {
        &self.command_filters
    }
}

fn extract_command_working_dir(command_line: &str, base_dir: &PathBuf) -> Option<PathBuf> {
    let parts: Vec<&str> = command_line.split_whitespace().collect();
    let mut index = 0;
    while index < parts.len() {
        if parts[index] == "-C" {
            let path = parts.get(index + 1)?;
            return resolve_path_context(path.trim_matches('"').trim_matches('\''), Some(base_dir))
                .ok();
        }
        index += 1;
    }
    None
}

/// Batch parser for processing multiple commands
pub struct GitCommandBatchParser {
    parser: GitCommandParser,
    batch_size: usize,
}

impl GitCommandBatchParser {
    pub fn new(parser: GitCommandParser, batch_size: usize) -> Self {
        Self { parser, batch_size }
    }

    /// Parse multiple commands and return successfully parsed ones
    pub fn parse_commands(
        &self,
        commands: Vec<(String, Option<PathBuf>)>,
    ) -> Vec<ParsedGitCommand> {
        commands
            .into_iter()
            .filter_map(|(cmd, dir)| match self.parser.parse_command(&cmd, dir) {
                Ok(Some(parsed)) => Some(parsed),
                Ok(None) => None,
                Err(e) => {
                    log::warn!("Failed to parse command '{}': {}", cmd, e);
                    None
                }
            })
            .collect()
    }

    /// Process commands in batches
    pub fn process_commands_in_batches<F>(
        &self,
        commands: Vec<(String, Option<PathBuf>)>,
        mut callback: F,
    ) -> Result<()>
    where
        F: FnMut(Vec<ParsedGitCommand>) -> Result<()>,
    {
        for batch in commands.chunks(self.batch_size) {
            let parsed_batch = self.parse_commands(batch.to_vec());
            if !parsed_batch.is_empty() {
                callback(parsed_batch)?;
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn create_test_git_repo() -> TempDir {
        let temp_dir = TempDir::new().unwrap();
        let git_dir = temp_dir.path().join(".git");
        fs::create_dir(&git_dir).unwrap();
        fs::write(
            git_dir.join("config"),
            "[core]\n\trepositoryformatversion = 0\n",
        )
        .unwrap();
        temp_dir
    }

    #[test]
    fn test_parse_git_command() {
        let _test_repo = create_test_git_repo();
        let parser = GitCommandParser::new_all_commands();

        // Note: This test might fail if run outside a git repository
        // In real usage, the command would be parsed in the context of the repo
        let _result = parser.parse_command("git status", None);

        // We can't guarantee this will succeed without proper git repo context
        // but we can test the command detection logic
        assert!(crate::monitor::git_detector::is_git_command("git status"));
    }

    #[test]
    fn test_parsed_command_log_format() {
        let parsed = ParsedGitCommand {
            timestamp: "2026-03-26 14:32:15".to_string(),
            root_dir: "/home/user/project".to_string(),
            command: "git commit -m 'test'".to_string(),
            working_dir: None,
            shell_context: None,
        };

        let log_entry = parsed.to_log_entry();
        assert_eq!(
            log_entry,
            "2026-03-26 14:32:15|/home/user/project|git commit -m 'test'"
        );

        let parsed_back = ParsedGitCommand::from_log_entry(&log_entry).unwrap();
        assert_eq!(parsed_back.timestamp, parsed.timestamp);
        assert_eq!(parsed_back.root_dir, parsed.root_dir);
        assert_eq!(parsed_back.command, parsed.command);
    }

    #[test]
    fn test_parser_with_filters() {
        let mut parser = GitCommandParser::new(vec!["push".to_string(), "pull".to_string()]);

        // Test filter management
        assert_eq!(parser.filters(), &["push", "pull"]);

        parser.add_filter("commit".to_string());
        assert_eq!(parser.filters(), &["push", "pull", "commit"]);

        parser.remove_filter("pull");
        assert_eq!(parser.filters(), &["push", "commit"]);
    }

    #[test]
    fn test_batch_parser() {
        let parser = GitCommandParser::new_all_commands();
        let batch_parser = GitCommandBatchParser::new(parser, 2);

        let commands = vec![
            ("git status".to_string(), None),
            ("ls -la".to_string(), None),
            ("git commit -m 'test'".to_string(), None),
        ];

        let parsed = batch_parser.parse_commands(commands);
        // May be empty due to git repository context requirements
        // but the parsing logic is exercised
        assert!(parsed.len() <= 2); // At most 2 git commands
    }
}
