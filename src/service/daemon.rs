use crate::config::Config;
use crate::monitor::{GitCommandParser, ParsedGitCommand};
use crate::service::logger::GitLogger;
use anyhow::{Context, Result};
use log::{debug, error, info, warn};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tokio::time::{sleep, Duration};

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
        let mut running = self.running.write().await;
        if *running {
            warn!("Service is already running");
            return Ok(());
        }
        *running = true;

        info!("Starting Git Monitor Daemon");

        // Initialize stats
        {
            let mut stats = self.stats.write().await;
            stats.start_time = Some(Instant::now());
            stats.last_activity = Some(Instant::now());
        }

        // Start logger service
        self.logger.start().await?;

        // Start monitoring loops
        self.start_monitoring_tasks().await?;

        info!("Git Monitor Daemon started successfully");

        // Keep service running
        let running = Arc::clone(&self.running);
        while *running.read().await {
            sleep(Duration::from_secs(1)).await;
        }

        Ok(())
    }

    /// Stop the daemon service
    pub async fn stop_service() -> Result<()> {
        info!("Stopping Git Monitor Daemon");
        // Note: In a real implementation, this would send a signal to the running daemon
        // For now, this is a placeholder
        Ok(())
    }

    /// Install as system service
    pub async fn install_service(_service_name: &str, _config: Config) -> Result<()> {
        info!("Installing Git Monitor as system service");

        #[cfg(windows)]
        {
            // TODO: Implement Windows service installation
            warn!("Windows service installation not yet implemented");
        }

        #[cfg(unix)]
        {
            // TODO: Implement systemd service installation
            warn!("Systemd service installation not yet implemented");
        }

        Ok(())
    }

    /// Uninstall system service
    pub async fn uninstall_service() -> Result<()> {
        info!("Uninstalling Git Monitor system service");

        #[cfg(windows)]
        {
            // TODO: Implement Windows service uninstallation
            warn!("Windows service uninstallation not yet implemented");
        }

        #[cfg(unix)]
        {
            // TODO: Implement systemd service uninstallation
            warn!("Systemd service uninstallation not yet implemented");
        }

        Ok(())
    }

    /// Check service status
    pub async fn service_status() -> Result<()> {
        info!("Checking Git Monitor service status");
        // TODO: Implement service status checking
        println!("Service status: Not implemented yet");
        Ok(())
    }

    /// Run in foreground (for testing/development)
    pub async fn run_foreground(&self) -> Result<()> {
        info!("Running Git Monitor in foreground mode");

        // Start logger
        self.logger.start().await?;

        // Simulate command monitoring (for testing)
        self.run_test_monitoring().await?;

        Ok(())
    }

    /// Start monitoring tasks
    async fn start_monitoring_tasks(&self) -> Result<()> {
        info!("Starting git command monitoring tasks");

        // For now, we'll just start a placeholder monitoring task
        // Real shell integration will be implemented in Phase 2
        let stats = Arc::clone(&self.stats);
        let logger = Arc::clone(&self.logger);
        let running = Arc::clone(&self.running);

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(10));

            while *running.read().await {
                interval.tick().await;

                // Update last activity
                {
                    let mut stats = stats.write().await;
                    stats.last_activity = Some(Instant::now());
                }

                // Log service heartbeat
                debug!("Git monitor daemon heartbeat");

                // Flush logger periodically
                if let Err(e) = logger.flush().await {
                    error!("Failed to flush logger: {}", e);
                }
            }
        });

        Ok(())
    }

    /// Run test monitoring (simulates git commands for testing)
    async fn run_test_monitoring(&self) -> Result<()> {
        info!("Running test monitoring mode");

        // Create some test git commands
        let test_commands = vec![
            "git status",
            "git add .",
            "git commit -m 'test commit'",
            "git push origin main",
            "git pull origin develop",
        ];

        for (i, cmd) in test_commands.iter().enumerate() {
            sleep(Duration::from_secs(2)).await;

            let parsed_cmd = ParsedGitCommand {
                timestamp: crate::utils::format_timestamp(),
                root_dir: format!("/test/repo{}", i),
                command: cmd.to_string(),
                working_dir: Some("/test".to_string()),
                shell_context: Some("test-shell".to_string()),
            };

            if let Err(e) = self.logger.log_command(parsed_cmd).await {
                error!("Failed to send test command: {}", e);
            } else {
                info!("Logged test command: {}", cmd);
            }

            // Update stats
            {
                let mut stats = self.stats.write().await;
                stats.commands_processed += 1;
                stats.commands_logged += 1;
                stats.last_activity = Some(Instant::now());
            }
        }

        // Keep running for a bit to allow processing
        info!("Test monitoring completed, keeping service active...");
        sleep(Duration::from_secs(5)).await;

        // Flush final logs
        self.logger.flush().await?;

        Ok(())
    }

    /// Process a git command (called by shell integration)
    pub async fn process_git_command(
        &self,
        command_line: &str,
        working_dir: Option<std::path::PathBuf>,
    ) -> Result<()> {
        let parser = self.parser.read().await;

        match parser.parse_command(command_line, working_dir)? {
            Some(parsed_cmd) => {
                self.logger
                    .log_command(parsed_cmd)
                    .await
                    .context("Failed to send command to logger")?;

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
}

// Platform-specific service management implementations

#[cfg(windows)]
mod windows_service {
    //! Windows Service implementation
    //! This will be implemented in Phase 2

    use super::*;

    pub async fn install_windows_service(_name: &str, _config: &Config) -> Result<()> {
        // TODO: Implement using windows-service crate
        warn!("Windows service installation will be implemented in Phase 2");
        Ok(())
    }

    pub async fn uninstall_windows_service(_name: &str) -> Result<()> {
        // TODO: Implement service removal
        warn!("Windows service uninstallation will be implemented in Phase 2");
        Ok(())
    }

    pub async fn get_windows_service_status(_name: &str) -> Result<String> {
        // TODO: Check service status
        Ok("Unknown".to_string())
    }
}

#[cfg(unix)]
mod unix_service {
    //! Unix/Linux systemd service implementation
    //! This will be implemented in Phase 2

    use super::*;

    pub async fn install_systemd_service(_name: &str, _config: &Config) -> Result<()> {
        // TODO: Create systemd service file
        warn!("Systemd service installation will be implemented in Phase 2");
        Ok(())
    }

    pub async fn uninstall_systemd_service(_name: &str) -> Result<()> {
        // TODO: Remove systemd service
        warn!("Systemd service uninstallation will be implemented in Phase 2");
        Ok(())
    }

    pub async fn get_systemd_service_status(_name: &str) -> Result<String> {
        // TODO: Check systemd service status
        Ok("Unknown".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
        let (_daemon, _temp_dir) = create_test_daemon().await;

        // Note: This test would need a proper git repository context
        // For now, we test that the function doesn't panic
        // Full testing will be done with integration tests
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
