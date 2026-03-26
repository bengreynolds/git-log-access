use crate::config::{Config, LogRotationConfig};
use crate::monitor::ParsedGitCommand;
use anyhow::{Context, Result};
use log::{debug, info, warn};
use std::collections::VecDeque;
use std::fs::OpenOptions;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::time;

/// Git command log entry
#[derive(Debug, Clone)]
pub struct LogEntry {
    pub command: ParsedGitCommand,
    pub received_at: Instant,
}

/// Logger service for writing git commands to log file
pub struct GitLogger {
    /// Path to the log file
    log_path: PathBuf,
    /// Log rotation configuration
    rotation_config: LogRotationConfig,
    /// Buffer for batching log writes
    buffer: Arc<Mutex<VecDeque<LogEntry>>>,
    /// Buffer size limit
    buffer_size: usize,
    /// Flush interval
    flush_interval: Duration,
}

impl GitLogger {
    /// Create new logger instance
    pub fn new(config: &Config) -> Result<Self> {
        if let Some(parent) = config.log_path.parent() {
            std::fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create log directory: {:?}", parent))?;
        }

        Ok(GitLogger {
            log_path: config.log_path.clone(),
            rotation_config: config.log_rotation.clone(),
            buffer: Arc::new(Mutex::new(VecDeque::new())),
            buffer_size: config.performance.log_buffer_size,
            flush_interval: Duration::from_secs(config.performance.flush_interval_seconds),
        })
    }

    /// Log a git command (async)
    pub async fn log_command(&self, command: ParsedGitCommand) -> Result<()> {
        let should_flush = {
            let mut buffer = self.buffer.lock().await;
            buffer.push_back(LogEntry {
                command,
                received_at: Instant::now(),
            });

            if buffer.len() > self.buffer_size * 2 {
                warn!("Log buffer overflow, dropping oldest entries");
                while buffer.len() > self.buffer_size {
                    buffer.pop_front();
                }
            }

            buffer.len() >= self.buffer_size
        };

        if should_flush {
            self.flush().await?;
        }

        Ok(())
    }

    /// Start the logger service (runs background task)
    pub async fn start(&self) -> Result<()> {
        info!("Starting Git Logger service");

        let buffer = Arc::clone(&self.buffer);
        let log_path = self.log_path.clone();
        let rotation_config = self.rotation_config.clone();
        let flush_interval = self.flush_interval;

        tokio::spawn(async move {
            let mut interval = time::interval(flush_interval);
            interval.set_missed_tick_behavior(time::MissedTickBehavior::Skip);

            loop {
                interval.tick().await;

                if let Err(e) = Self::flush_buffer(&buffer, &log_path, &rotation_config).await {
                    log::error!("Failed to flush log buffer: {}", e);
                }
            }
        });

        Ok(())
    }

    /// Flush buffered entries to disk
    async fn flush_buffer(
        buffer: &Arc<Mutex<VecDeque<LogEntry>>>,
        log_path: &Path,
        rotation_config: &LogRotationConfig,
    ) -> Result<()> {
        let mut buffer = buffer.lock().await;

        if buffer.is_empty() {
            return Ok(());
        }

        debug!("Flushing {} log entries to disk", buffer.len());

        if rotation_config.enabled {
            Self::check_and_rotate_log(log_path, rotation_config)?;
        }

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(log_path)
            .with_context(|| format!("Failed to open log file: {:?}", log_path))?;

        let mut writer = BufWriter::new(&mut file);

        while let Some(entry) = buffer.pop_front() {
            let log_line = entry.command.to_log_entry();
            writeln!(writer, "{}", log_line)
                .with_context(|| format!("Failed to write log entry: {}", log_line))?;
        }

        writer.flush().context("Failed to flush log file")?;

        debug!("Successfully flushed log entries");
        Ok(())
    }

    /// Check if log rotation is needed and perform rotation
    fn check_and_rotate_log(log_path: &Path, config: &LogRotationConfig) -> Result<()> {
        if !config.enabled {
            return Ok(());
        }

        let metadata = match std::fs::metadata(log_path) {
            Ok(meta) => meta,
            Err(_) => return Ok(()),
        };

        let file_size_mb = metadata.len() / (1024 * 1024);

        if file_size_mb >= config.max_size_mb {
            info!(
                "Log file size ({} MB) exceeds limit ({} MB), rotating logs",
                file_size_mb, config.max_size_mb
            );
            Self::rotate_log_files(log_path, config.keep_files)?;
        }

        Ok(())
    }

    /// Rotate log files (move current to .1, .1 to .2, etc.)
    fn rotate_log_files(log_path: &Path, keep_files: u32) -> Result<()> {
        let log_dir = log_path
            .parent()
            .context("Log file has no parent directory")?;
        let log_stem = log_path.file_stem().context("Log file has no stem")?;
        let log_ext = log_path
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("log");

        if keep_files > 0 {
            let oldest_path = log_dir.join(format!(
                "{}.{}.{}",
                log_stem.to_string_lossy(),
                keep_files,
                log_ext
            ));
            if oldest_path.exists() {
                std::fs::remove_file(&oldest_path)
                    .with_context(|| format!("Failed to remove old log file: {:?}", oldest_path))?;
            }
        }

        for i in (1..keep_files).rev() {
            let old_path =
                log_dir.join(format!("{}.{}.{}", log_stem.to_string_lossy(), i, log_ext));
            let new_path = log_dir.join(format!(
                "{}.{}.{}",
                log_stem.to_string_lossy(),
                i + 1,
                log_ext
            ));

            if old_path.exists() {
                std::fs::rename(&old_path, &new_path).with_context(|| {
                    format!(
                        "Failed to rotate log file: {:?} -> {:?}",
                        old_path, new_path
                    )
                })?;
            }
        }

        if keep_files > 0 {
            let new_path = log_dir.join(format!("{}.1.{}", log_stem.to_string_lossy(), log_ext));
            std::fs::rename(log_path, &new_path).with_context(|| {
                format!(
                    "Failed to rotate current log file: {:?} -> {:?}",
                    log_path, new_path
                )
            })?;
        }

        Ok(())
    }

    /// Get current buffer size
    pub async fn buffer_size(&self) -> usize {
        self.buffer.lock().await.len()
    }

    /// Force flush all buffered entries
    pub async fn flush(&self) -> Result<()> {
        Self::flush_buffer(&self.buffer, &self.log_path, &self.rotation_config).await
    }

    /// Stop the logger and flush remaining entries
    pub async fn stop(&self) -> Result<()> {
        info!("Stopping Git Logger service");
        self.flush().await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use tempfile::TempDir;
    use tokio::time::{sleep, Duration};

    async fn create_test_logger() -> (GitLogger, TempDir) {
        let temp_dir = TempDir::new().unwrap();
        let mut config = Config::test_config();
        config.log_path = temp_dir.path().join("test.log");

        let logger = GitLogger::new(&config).unwrap();
        (logger, temp_dir)
    }

    #[tokio::test]
    async fn test_logger_creation() {
        let (logger, _temp_dir) = create_test_logger().await;
        assert_eq!(logger.buffer_size().await, 0);
    }

    #[tokio::test]
    async fn test_log_command() {
        let (logger, _temp_dir) = create_test_logger().await;

        let command = crate::monitor::ParsedGitCommand {
            timestamp: "2026-03-26 14:32:15".to_string(),
            root_dir: "/test/repo".to_string(),
            command: "git status".to_string(),
            working_dir: None,
            shell_context: None,
        };

        logger.log_command(command).await.unwrap();

        sleep(Duration::from_millis(100)).await;

        assert!(logger.buffer_size().await > 0 || std::fs::metadata(&logger.log_path).is_ok());
    }

    #[tokio::test]
    async fn test_log_flush() {
        let (logger, temp_dir) = create_test_logger().await;
        let log_file = temp_dir.path().join("test.log");

        let command = crate::monitor::ParsedGitCommand {
            timestamp: "2026-03-26 14:32:15".to_string(),
            root_dir: "/test/repo".to_string(),
            command: "git commit -m 'test'".to_string(),
            working_dir: None,
            shell_context: None,
        };

        logger.log_command(command).await.unwrap();
        logger.flush().await.unwrap();

        let content = std::fs::read_to_string(&log_file).unwrap();
        assert!(content.contains("git commit -m 'test'"));
        assert!(content.contains("2026-03-26 14:32:15"));
        assert!(content.contains("/test/repo"));
    }
}
