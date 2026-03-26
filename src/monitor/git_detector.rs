use std::collections::HashSet;
use once_cell::sync::Lazy;

/// Set of git commands to monitor
static GIT_COMMANDS: Lazy<HashSet<&'static str>> = Lazy::new(|| {
    [
        // Core git commands
        "git",
        // Common git subcommands we want to capture
        "add", "commit", "push", "pull", "fetch", "clone", "checkout", "branch",
        "merge", "rebase", "reset", "revert", "status", "log", "diff", "init",
        "remote", "tag", "stash", "cherry-pick", "bisect", "blame", "show",
        "config", "clean", "mv", "rm", "help",
        // Git aliases that might be used
        "ci", "co", "st", "br", // common aliases for commit, checkout, status, branch
    ].into_iter().collect()
});

/// Sensitive git arguments that should be sanitized from logs
static SENSITIVE_ARGS: Lazy<HashSet<&'static str>> = Lazy::new(|| {
    [
        // Authentication-related
        "--password",
        "--token",
        "--credential",
        "--askpass",
        // Configuration that might contain sensitive data
        "user.password",
        "credential.",
        "http.proxy",
        "https.proxy",
    ].into_iter().collect()
});

/// Check if a command line is a git command
pub fn is_git_command(command_line: &str) -> bool {
    if command_line.trim().is_empty() {
        return false;
    }
    
    let parts: Vec<&str> = command_line.trim().split_whitespace().collect();
    if parts.is_empty() {
        return false;
    }
    
    // Check if the first part is 'git' or a git command
    let first_command = parts[0];
    
    // Direct git command
    if first_command.ends_with("git") || first_command.ends_with("git.exe") {
        return true;
    }
    
    // Git subcommand used directly (less common but possible)
    if GIT_COMMANDS.contains(&first_command) && parts.len() > 1 {
        return true;
    }
    
    false
}

/// Extract git command from command line, sanitizing sensitive information
pub fn extract_git_command(command_line: &str) -> Option<String> {
    if !is_git_command(command_line) {
        return None;
    }
    
    let sanitized = sanitize_command(command_line);
    Some(sanitized)
}

/// Sanitize git command by removing or masking sensitive arguments
fn sanitize_command(command_line: &str) -> String {
    let parts: Vec<&str> = command_line.trim().split_whitespace().collect();
    let mut sanitized_parts = Vec::new();
    let mut skip_next = false;
    
    for (i, part) in parts.iter().enumerate() {
        if skip_next {
            sanitized_parts.push("***");
            skip_next = false;
            continue;
        }
        
        // Check if this part is a sensitive argument
        let is_sensitive = SENSITIVE_ARGS.iter().any(|&sensitive| {
            part.starts_with(sensitive) || part.contains(sensitive)
        });
        
        if is_sensitive {
            if part.contains('=') {
                // Format: --password=secret -> --password=***
                if let Some(eq_pos) = part.find('=') {
                    let key = &part[..eq_pos + 1];
                    sanitized_parts.push(format!("{}***", key));
                } else {
                    sanitized_parts.push("***".to_string());
                }
            } else {
                // Format: --password secret -> --password ***
                sanitized_parts.push(part.to_string());
                skip_next = true;
            }
        } else {
            sanitized_parts.push(part.to_string());
        }
    }
    
    sanitized_parts.join(" ")
}

/// Determine if this command should be logged based on configuration
pub fn should_log_command(command: &str, config_filters: &[String]) -> bool {
    // Always log if no filters specified
    if config_filters.is_empty() {
        return true;
    }
    
    // Check against configured filters
    for filter in config_filters {
        if command.contains(filter) {
            return true;
        }
    }
    
    false
}

/// Extract the main git operation from a command (e.g., "push", "commit", "pull")
pub fn extract_git_operation(command: &str) -> Option<String> {
    let parts: Vec<&str> = command.trim().split_whitespace().collect();
    
    if parts.len() < 2 {
        return None;
    }
    
    // Skip 'git' and get the subcommand
    if parts[0].ends_with("git") || parts[0].ends_with("git.exe") {
        return Some(parts[1].to_string());
    }
    
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_git_command() {
        assert!(is_git_command("git status"));
        assert!(is_git_command("git commit -m 'test'"));
        assert!(is_git_command("/usr/bin/git push"));
        assert!(is_git_command("C:\\Program Files\\Git\\bin\\git.exe pull"));
        
        assert!(!is_git_command("ls -la"));
        assert!(!is_git_command("npm install"));
        assert!(!is_git_command(""));
        assert!(!is_git_command("   "));
    }

    #[test]
    fn test_extract_git_command() {
        let cmd = extract_git_command("git status");
        assert_eq!(cmd, Some("git status".to_string()));
        
        let cmd = extract_git_command("ls -la");
        assert_eq!(cmd, None);
    }

    #[test]
    fn test_sanitize_command() {
        let cmd = "git config user.password secret123";
        let sanitized = sanitize_command(cmd);
        assert!(sanitized.contains("***"));
        assert!(!sanitized.contains("secret123"));
        
        let cmd = "git push --token=abc123 origin main";
        let sanitized = sanitize_command(cmd);
        assert!(sanitized.contains("--token=***"));
        assert!(!sanitized.contains("abc123"));
    }

    #[test]
    fn test_extract_git_operation() {
        assert_eq!(extract_git_operation("git push origin main"), Some("push".to_string()));
        assert_eq!(extract_git_operation("git commit -m 'test'"), Some("commit".to_string()));
        assert_eq!(extract_git_operation("git"), None);
        assert_eq!(extract_git_operation(""), None);
    }

    #[test]
    fn test_should_log_command() {
        let filters = vec![];
        assert!(should_log_command("git status", &filters));
        
        let filters = vec!["push".to_string(), "pull".to_string()];
        assert!(should_log_command("git push origin main", &filters));
        assert!(should_log_command("git pull", &filters));
        assert!(!should_log_command("git status", &filters));
    }
}