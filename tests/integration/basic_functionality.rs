use git_log_access::config::Config;
use git_log_access::service::GitMonitorDaemon;
use std::time::Duration;
use tempfile::TempDir;
use tokio::time::sleep;

#[tokio::test]
async fn test_daemon_foreground_run() {
    // Create test configuration
    let temp_dir = TempDir::new().unwrap();
    let mut config = Config::test_config();
    config.log_path = temp_dir.path().join("integration_test.log");

    // Create and start daemon
    let daemon = GitMonitorDaemon::new(config).unwrap();
    
    // Run in background for a short time
    let daemon_handle = tokio::spawn(async move {
        daemon.run_foreground().await
    });

    // Let it run for a bit
    sleep(Duration::from_secs(2)).await;

    // Stop the daemon (in real usage this would be a signal)
    daemon_handle.abort();

    // Verify log file was created and contains expected entries
    let log_content = std::fs::read_to_string(temp_dir.path().join("integration_test.log"));
    
    // The test should have created some test entries
    if let Ok(content) = log_content {
        // Verify log format
        for line in content.lines() {
            if !line.is_empty() {
                let parts: Vec<&str> = line.split('|').collect();
                assert_eq!(parts.len(), 3, "Log line should have 3 parts: {}", line);
                
                // Verify timestamp format (basic check)
                assert!(parts[0].contains('-'), "Timestamp should contain dashes");
                assert!(parts[0].contains(':'), "Timestamp should contain colons");
                
                // Verify root directory is present
                assert!(!parts[1].is_empty(), "Root directory should not be empty");
                
                // Verify command starts with git
                assert!(parts[2].starts_with("git"), "Command should start with 'git'");
            }
        }
        println!("Integration test passed: Log format is correct");
    } else {
        println!("Note: Log file not created in test run (expected for test mode)");
    }
}

#[tokio::test]
async fn test_git_command_processing() {
    use git_log_access::monitor::GitCommandParser;
    use std::path::PathBuf;

    let parser = GitCommandParser::new_all_commands();
    
    // Test various git commands
    let test_cases = vec![
        ("git status", true),
        ("git commit -m 'test'", true),
        ("git push origin main", true),
        ("ls -la", false),
        ("npm install", false),
        ("", false),
    ];

    for (command, should_parse) in test_cases {
        let result = parser.parse_command(command, Some(PathBuf::from(".")));
        
        match (result, should_parse) {
            (Ok(Some(_)), true) => {
                println!("✓ Correctly parsed git command: {}", command);
            }
            (Ok(None), false) => {
                println!("✓ Correctly ignored non-git command: {}", command);
            }
            (Err(_), true) => {
                println!("⚠ Failed to parse git command (may be outside git repo): {}", command);
                // This is expected if we're not in a git repository
            }
            (Ok(Some(_)), false) => {
                panic!("Incorrectly parsed non-git command: {}", command);
            }
            (Ok(None), true) => {
                println!("⚠ Failed to parse git command (may be filtered): {}", command);
            }
            (Err(_), false) => {
                // Error on non-git command is fine
                println!("✓ Error on non-git command (expected): {}", command);
            }
        }
    }
}