use crate::config::Config;
use crate::monitor::GitCommandParser;
use crate::service::{GitLogger, HookManager, HookStatus};
use anyhow::{Context, Result};
use log::info;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;

/// Background service daemon for git command monitoring
pub struct GitMonitorDaemon {
    /// Configuration
    config: Config,
    /// Command parser
    parser: Arc<RwLock<GitCommandParser>>,
    /// Logger service
    logger: Arc<GitLogger>,
    /// Running state
    running: Arc<RwLock<bool>>,
    /// Service statistics
    stats: Arc<RwLock<ServiceStats>>,
}

/// Service statistics
#[derive(Debug, Default, Clone)]
pub struct ServiceStats {
    /// Total commands processed
    pub commands_processed: u64,
    /// Total commands logged
    pub commands_logged: u64,
    /// Service start time
    pub start_time: Option<Instant>,
    /// Last activity time
    pub last_activity: Option<Instant>,
    /// Error count
    pub error_count: u64,
}

impl GitMonitorDaemon {
    /// Create new daemon instance
    pub fn new(config: Config) -> Result<Self> {
        // Validate configuration
        config.validate()?;

        // Create command parser with no filters (log all git commands)
        let parser = GitCommandParser::new_all_commands();

        // Create logger
        let logger = GitLogger::new(&config)?;

        Ok(GitMonitorDaemon {
            config,
            parser: Arc::new(RwLock::new(parser)),
            logger: Arc::new(logger),
            running: Arc::new(RwLock::new(false)),
            stats: Arc::new(RwLock::new(ServiceStats::default())),
        })
    }

    /// Start the daemon service
    pub async fn start_service(&self) -> Result<()> {
        info!("Enabling Git Monitor shell interception");

        // Initialize stats
        {
            let mut stats = self.stats.write().await;
            stats.start_time = Some(Instant::now());
            stats.last_activity = Some(Instant::now());
        }

        let _path = self.config.ensure_default_file()?;
        let status = HookManager::install(&self.config)?;
        Self::print_status(&status);
        Ok(())
    }

    /// Stop the daemon service
    pub async fn stop_service() -> Result<()> {
        info!("Stopping Git Monitor Daemon");
        let config = Config::load_or_default(None)?;
        HookManager::set_enabled(&config, false)?;
        Ok(())
    }

    /// Install as system service
    pub async fn install_service(_service_name: &str, config: Config) -> Result<()> {
        info!("Installing Git Monitor shell hooks");
        let _path = config.ensure_default_file()?;
        let status = HookManager::install(&config)?;
        Self::print_status(&status);
        Ok(())
    }

    /// Uninstall system service
    pub async fn uninstall_service() -> Result<()> {
        info!("Uninstalling Git Monitor shell hooks");
        let config = Config::load_or_default(None)?;
        let status = HookManager::uninstall(&config)?;
        Self::print_status(&status);
        Ok(())
    }

    /// Check service status
    pub async fn service_status() -> Result<()> {
        info!("Checking Git Monitor service status");
        let config = Config::load_or_default(None)?;
        let status = HookManager::status(&config)?;
        Self::print_status(&status);
        Ok(())
    }

    /// Run in foreground (for testing/development)
    pub async fn run_foreground(&self) -> Result<()> {
        info!("Running Git Monitor in foreground mode");

        let _path = self.config.ensure_default_file()?;
        let status = HookManager::install(&self.config)?;
        Self::print_status(&status);
        info!("Foreground mode active. Press Ctrl+C to disable interception and exit.");
        tokio::signal::ctrl_c()
            .await
            .context("Failed while waiting for Ctrl+C")?;
        HookManager::set_enabled(&self.config, false)?;
        Ok(())
    }

    /// Process a git command (called by shell integration)
    pub async fn process_git_command(
        &self,
        command_line: &str,
        working_dir: Option<std::path::PathBuf>,
    ) -> Result<()> {
        self.process_git_command_with_context(command_line, working_dir, None)
            .await
    }

    /// Process a git command (called by shell integration)
    pub async fn process_git_command_with_context(
        &self,
        command_line: &str,
        working_dir: Option<std::path::PathBuf>,
        shell_context: Option<String>,
    ) -> Result<()> {
        let parser = self.parser.read().await;

        match parser.parse_command_with_context(command_line, working_dir, shell_context)? {
            Some(parsed_cmd) => {
                self.logger
                    .log_command(parsed_cmd)
                    .await
                    .context("Failed to send command to logger")?;
                self.logger.flush().await?;

                // Update stats
                {
                    let mut stats = self.stats.write().await;
                    stats.commands_processed += 1;
                    stats.commands_logged += 1;
                    stats.last_activity = Some(Instant::now());
                }
            }
            None => {
                // Not a git command or filtered out
                let mut stats = self.stats.write().await;
                stats.commands_processed += 1;
                stats.last_activity = Some(Instant::now());
            }
        }

        Ok(())
    }

    /// Get service statistics
    pub async fn get_stats(&self) -> ServiceStats {
        self.stats.read().await.clone()
    }

    /// Update parser filters
    pub async fn update_filters(&self, filters: Vec<String>) {
        let mut parser = self.parser.write().await;
        parser.set_filters(filters);
    }

    /// Stop the daemon
    pub async fn stop(&self) -> Result<()> {
        info!("Stopping Git Monitor Daemon");

        {
            let mut running = self.running.write().await;
            *running = false;
        }

        // Stop logger
        self.logger.stop().await?;

        info!("Git Monitor Daemon stopped");
        Ok(())
    }

    /// Get configuration
    pub fn config(&self) -> &Config {
        &self.config
    }

    fn print_status(status: &HookStatus) {
        println!(
            "Interception: {}",
            if status.enabled {
                "enabled"
            } else {
                "disabled"
            }
        );
        for target in &status.targets {
            if target.supported {
                println!(
                    "{}: {} ({})",
                    target.shell,
                    if target.installed {
                        "installed"
                    } else {
                        "missing"
                    },
                    target.path.display()
                );
            } else {
                println!("{}: unsupported", target.shell);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    async fn create_test_daemon() -> (GitMonitorDaemon, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let mut config = Config::test_config();
        config.log_path = temp_dir.path().join("test.log");

        let daemon = GitMonitorDaemon::new(config).unwrap();
        (daemon, temp_dir)
    }

    #[tokio::test]
    async fn test_daemon_creation() {
        let (daemon, _temp_dir) = create_test_daemon().await;
        assert_eq!(*daemon.running.read().await, false);

        let stats = daemon.get_stats().await;
        assert_eq!(stats.commands_processed, 0);
        assert_eq!(stats.commands_logged, 0);
    }

    #[tokio::test]
    async fn test_process_git_command() {
        let (daemon, temp_dir) = create_test_daemon().await;
        let repo_dir = temp_dir.path().join("repo");
        fs::create_dir_all(repo_dir.join(".git")).unwrap();
        fs::write(
            repo_dir.join(".git").join("config"),
            "[core]\n\trepositoryformatversion = 0\n",
        )
        .unwrap();

        daemon
            .process_git_command_with_context(
                "git status",
                Some(repo_dir.clone()),
                Some("test-shell".to_string()),
            )
            .await
            .unwrap();

        let content = fs::read_to_string(temp_dir.path().join("test.log")).unwrap();
        assert!(content.contains("git status"));
    }

    #[tokio::test]
    async fn test_update_filters() {
        let (daemon, _temp_dir) = create_test_daemon().await;

        let filters = vec!["push".to_string(), "pull".to_string()];
        daemon.update_filters(filters.clone()).await;

        let parser = daemon.parser.read().await;
        assert_eq!(parser.filters(), &filters);
    }
}
