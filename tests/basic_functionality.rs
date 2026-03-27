use git_log_access::config::Config;
use git_log_access::monitor::ParsedGitCommand;
use git_log_access::service::GitMonitorDaemon;
use std::fs;
use std::path::PathBuf;
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

#[tokio::test]
async fn test_daemon_logs_real_processed_command() {
    let repo_dir = create_test_git_repo();
    let log_dir = TempDir::new().unwrap();
    let mut config = Config::test_config();
    config.log_path = log_dir.path().join("integration_test.log");

    let daemon = GitMonitorDaemon::new(config).unwrap();
    daemon
        .process_git_command_with_context(
            "git status",
            Some(repo_dir.path().to_path_buf()),
            Some("integration-shell".to_string()),
        )
        .await
        .unwrap();

    let content = fs::read_to_string(log_dir.path().join("integration_test.log")).unwrap();
    let line = content.lines().next().unwrap();
    let parsed = ParsedGitCommand::from_log_entry(line).unwrap();
    assert!(parsed.timestamp.contains('-'));
    assert!(parsed.timestamp.contains(':'));
    assert!(parsed.command.starts_with("git"));
}

#[tokio::test]
async fn test_git_command_processing() {
    use git_log_access::monitor::GitCommandParser;

    let repo_dir = create_test_git_repo();
    let parser = GitCommandParser::new_all_commands();

    let test_cases = vec![
        ("git status", true),
        ("git commit -m 'test'", true),
        ("git push origin main", true),
        ("ls -la", false),
        ("npm install", false),
        ("", false),
    ];

    for (command, should_parse) in test_cases {
        let result = parser.parse_command(command, Some(PathBuf::from(repo_dir.path())));

        match (result, should_parse) {
            (Ok(Some(_)), true) => {}
            (Ok(None), false) => {}
            (Ok(Some(_)), false) => {
                panic!("Incorrectly parsed non-git command: {}", command);
            }
            (Ok(None), true) | (Err(_), true) => {
                panic!("Failed to parse git command: {}", command);
            }
            (Err(_), false) => {}
        }
    }
}
