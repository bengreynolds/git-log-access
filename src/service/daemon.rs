use crate::config::Config;
use crate::monitor::GitCommandParser;
use crate::service::{GitLogger, HookManager, HookStatus, ProcessMonitor};
use anyhow::{Context, Result};
use log::info;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tokio::time::{sleep, Duration};

const PID_FILE_NAME: &str = "daemon.pid";

/// Background service daemon for git command monitoring
pub struct GitMonitorDaemon {
    /// Configuration
    config: Config,
    /// Command parser
    pub(crate) parser: Arc<RwLock<GitCommandParser>>,
    /// Logger service
    pub(crate) logger: Arc<GitLogger>,
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
        config.validate()?;

        let parser = GitCommandParser::new_all_commands();
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
        self.initialize_stats().await;

        let config_path = self.config.ensure_default_file()?;
        HookManager::install(&self.config)?;

        if Self::background_daemon_running()? {
            info!("Background process monitor is already running");
        } else {
            Self::spawn_background_daemon(&config_path)?;
            for _ in 0..20 {
                if Self::background_daemon_running()? {
                    break;
                }
                sleep(Duration::from_millis(100)).await;
            }
        }

        Self::print_status(
            &HookManager::status(&self.config)?,
            Self::background_daemon_running()?,
        );
        Ok(())
    }

    /// Stop the daemon service
    pub async fn stop_service() -> Result<()> {
        info!("Stopping Git Monitor Daemon");
        let config = Config::load_or_default(None)?;
        HookManager::set_enabled(&config, false)?;
        Self::stop_background_daemon()?;
        Ok(())
    }

    /// Install shell hooks
    pub async fn install_service(_service_name: &str, config: Config) -> Result<()> {
        info!("Installing Git Monitor shell hooks");
        let _path = config.ensure_default_file()?;
        let status = HookManager::install(&config)?;
        Self::print_status(&status, Self::background_daemon_running()?);
        Ok(())
    }

    /// Uninstall shell hooks
    pub async fn uninstall_service() -> Result<()> {
        info!("Uninstalling Git Monitor shell hooks");
        let config = Config::load_or_default(None)?;
        let status = HookManager::uninstall(&config)?;
        Self::stop_background_daemon()?;
        Self::print_status(&status, false);
        Ok(())
    }

    /// Check service status
    pub async fn service_status() -> Result<()> {
        info!("Checking Git Monitor service status");
        let config = Config::load_or_default(None)?;
        let status = HookManager::status(&config)?;
        Self::print_status(&status, Self::background_daemon_running()?);
        Ok(())
    }

    /// Run in foreground (for testing/development)
    pub async fn run_foreground(&self) -> Result<()> {
        info!("Running Git Monitor in foreground mode");
        self.initialize_stats().await;

        let _path = self.config.ensure_default_file()?;
        let status = HookManager::install(&self.config)?;
        Self::print_status(&status, false);
        info!("Foreground mode active. Press Ctrl+C to disable interception and exit.");
        self.run_process_monitor_until_ctrl_c().await?;
        HookManager::set_enabled(&self.config, false)?;
        Ok(())
    }

    pub async fn run_background_daemon(&self) -> Result<()> {
        self.initialize_stats().await;
        HookManager::set_enabled(&self.config, true)?;
        Self::write_pid_file(std::process::id())?;
        let result = self.run_process_monitor_loop().await;
        let _ = Self::clear_pid_file();
        result
    }

    /// Process a git command (called by shell integration)
    pub async fn process_git_command(
        &self,
        command_line: &str,
        working_dir: Option<PathBuf>,
    ) -> Result<()> {
        self.process_git_command_with_context(command_line, working_dir, None)
            .await
    }

    /// Process a git command (called by shell integration)
    pub async fn process_git_command_with_context(
        &self,
        command_line: &str,
        working_dir: Option<PathBuf>,
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

                let mut stats = self.stats.write().await;
                stats.commands_processed += 1;
                stats.commands_logged += 1;
                stats.last_activity = Some(Instant::now());
            }
            None => {
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

        let mut running = self.running.write().await;
        *running = false;

        self.logger.stop().await?;

        info!("Git Monitor Daemon stopped");
        Ok(())
    }

    /// Get configuration
    pub fn config(&self) -> &Config {
        &self.config
    }

    async fn initialize_stats(&self) {
        let mut stats = self.stats.write().await;
        stats.start_time = Some(Instant::now());
        stats.last_activity = Some(Instant::now());
    }

    async fn run_process_monitor_until_ctrl_c(&self) -> Result<()> {
        let mut monitor = ProcessMonitor::new();
        loop {
            tokio::select! {
                result = monitor.poll_once(self) => {
                    result?;
                }
                _ = tokio::signal::ctrl_c() => {
                    return Ok(());
                }
            }
            tokio::select! {
                _ = sleep(Duration::from_secs(1)) => {}
                _ = tokio::signal::ctrl_c() => {
                    return Ok(());
                }
            }
        }
    }

    async fn run_process_monitor_loop(&self) -> Result<()> {
        let mut monitor = ProcessMonitor::new();
        monitor.run(self).await
    }

    fn print_status(status: &HookStatus, daemon_running: bool) {
        println!(
            "Interception: {}",
            if status.enabled {
                "enabled"
            } else {
                "disabled"
            }
        );
        println!(
            "Process monitor: {}",
            if daemon_running { "running" } else { "stopped" }
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

    fn spawn_background_daemon(config_path: &Path) -> Result<()> {
        let exe = std::env::current_exe().context("Failed to determine executable path")?;
        let mut command = Command::new(exe);
        command
            .arg("daemon")
            .arg("--config")
            .arg(config_path)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());

        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }

        command
            .spawn()
            .context("Failed to start background daemon")?;
        Ok(())
    }

    fn stop_background_daemon() -> Result<()> {
        let pid = match Self::read_pid_file()? {
            Some(pid) => pid,
            None => return Ok(()),
        };

        if Self::is_pid_running(pid)? {
            #[cfg(windows)]
            {
                Command::new("taskkill")
                    .args(["/PID", &pid.to_string(), "/F"])
                    .output()
                    .context("Failed to stop background daemon")?;
            }
            #[cfg(unix)]
            {
                Command::new("kill")
                    .args(["-TERM", &pid.to_string()])
                    .output()
                    .context("Failed to stop background daemon")?;
            }
        }

        Self::clear_pid_file()?;
        Ok(())
    }

    fn background_daemon_running() -> Result<bool> {
        match Self::read_pid_file()? {
            Some(pid) => Self::is_pid_running(pid),
            None => Ok(false),
        }
    }

    fn pid_file_path() -> Result<PathBuf> {
        Ok(Config::default_state_dir()?.join(PID_FILE_NAME))
    }

    fn write_pid_file(pid: u32) -> Result<()> {
        let path = Self::pid_file_path()?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create state directory: {:?}", parent))?;
        }
        fs::write(&path, pid.to_string())
            .with_context(|| format!("Failed to write pid file: {:?}", path))?;
        Ok(())
    }

    fn read_pid_file() -> Result<Option<u32>> {
        let path = Self::pid_file_path()?;
        if !path.exists() {
            return Ok(None);
        }
        let content = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read pid file: {:?}", path))?;
        Ok(content.trim().parse::<u32>().ok())
    }

    fn clear_pid_file() -> Result<()> {
        let path = Self::pid_file_path()?;
        if path.exists() {
            fs::remove_file(&path)
                .with_context(|| format!("Failed to remove pid file: {:?}", path))?;
        }
        Ok(())
    }

    fn is_pid_running(pid: u32) -> Result<bool> {
        #[cfg(windows)]
        {
            let output = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-Command",
                    &format!(
                        "if (Get-Process -Id {pid} -ErrorAction SilentlyContinue) {{ 'running' }}"
                    ),
                ])
                .output()
                .context("Failed to query daemon process state")?;
            Ok(String::from_utf8_lossy(&output.stdout).contains("running"))
        }
        #[cfg(unix)]
        {
            Ok(Command::new("kill")
                .args(["-0", &pid.to_string()])
                .status()
                .context("Failed to query daemon process state")?
                .success())
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
