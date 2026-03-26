use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

pub mod settings;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Path to the log file
    pub log_path: PathBuf,
    /// Device nickname for identification
    pub device_nickname: String,
    /// Enabled shell environments
    pub enabled_shells: Vec<String>,
    /// Monitoring scope: "user", "system", or "directory"
    pub monitor_scope: String,
    /// Log rotation configuration
    pub log_rotation: LogRotationConfig,
    /// Performance constraints
    pub performance: PerformanceConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogRotationConfig {
    /// Enable log rotation
    pub enabled: bool,
    /// Maximum log file size in MB
    pub max_size_mb: u64,
    /// Number of rotated files to keep
    pub keep_files: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceConfig {
    /// Maximum memory usage in MB
    pub max_memory_mb: u64,
    /// Log buffer size (number of entries to buffer before writing)
    pub log_buffer_size: usize,
    /// Flush interval in seconds
    pub flush_interval_seconds: u64,
}

impl Config {
    /// Default configuration directory
    pub fn default_config_dir() -> Result<PathBuf> {
        #[cfg(windows)]
        {
            let appdata = std::env::var("APPDATA").or_else(|_| std::env::var("USERPROFILE"));
            let base = appdata.context("Could not determine config directory")?;
            Ok(PathBuf::from(base).join("git-monitor"))
        }
        #[cfg(unix)]
        {
            let config_home = std::env::var("XDG_CONFIG_HOME")
                .or_else(|_| std::env::var("HOME").map(|home| format!("{home}/.config")))
                .context("Could not determine config directory")?;
            Ok(PathBuf::from(config_home).join("git-monitor"))
        }
    }

    /// Default configuration path
    pub fn default_config_path() -> Result<PathBuf> {
        Ok(Self::default_config_dir()?.join(crate::DEFAULT_CONFIG_NAME))
    }

    /// State directory used by hook-based monitoring
    pub fn default_state_dir() -> Result<PathBuf> {
        Self::default_config_dir()
    }

    /// Load configuration from file
    pub fn from_file(path: &str) -> Result<Self> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read config file: {}", path))?;

        serde_json::from_str(&content)
            .with_context(|| format!("Failed to parse config file: {}", path))
    }

    /// Save configuration to file
    pub fn to_file(&self, path: &str) -> Result<()> {
        if let Some(parent) = PathBuf::from(path).parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create config directory: {:?}", parent))?;
        }

        let content = serde_json::to_string_pretty(self)?;
        fs::write(path, content)
            .with_context(|| format!("Failed to write config file: {}", path))?;
        Ok(())
    }

    /// Load the configured file if it exists, otherwise create an in-memory default config
    pub fn load_or_default(config_path: Option<&str>) -> Result<Self> {
        match config_path {
            Some(path) => Self::from_file(path),
            None => {
                let default_path = Self::default_config_path()?;
                if default_path.exists() {
                    Self::from_file(&default_path.to_string_lossy())
                } else {
                    Self::default_config()
                }
            }
        }
    }

    /// Persist the config to the default path when no explicit path is supplied
    pub fn ensure_default_file(&self) -> Result<PathBuf> {
        let path = Self::default_config_path()?;
        if !path.exists() {
            self.to_file(&path.to_string_lossy())?;
        }
        Ok(path)
    }

    /// Create default configuration
    pub fn default_config() -> Result<Self> {
        let hostname = Self::get_hostname().unwrap_or_else(|| "unknown".to_string());
        let default_log_dir = Self::get_default_log_dir()?;

        Ok(Config {
            log_path: default_log_dir.join(format!("{}_githistory.log", hostname)),
            device_nickname: hostname,
            enabled_shells: Self::detect_available_shells(),
            monitor_scope: "user".to_string(),
            log_rotation: LogRotationConfig {
                enabled: true,
                max_size_mb: 100,
                keep_files: 10,
            },
            performance: PerformanceConfig {
                max_memory_mb: crate::MAX_MEMORY_MB,
                log_buffer_size: 1000,
                flush_interval_seconds: 30,
            },
        })
    }

    /// Get system hostname
    fn get_hostname() -> Option<String> {
        #[cfg(windows)]
        {
            std::env::var("COMPUTERNAME").ok()
        }
        #[cfg(unix)]
        {
            use std::ffi::CStr;
            use std::mem;

            unsafe {
                let mut buffer = [0u8; 256];
                if libc::gethostname(buffer.as_mut_ptr() as *mut i8, buffer.len()) == 0 {
                    let cstr = CStr::from_ptr(buffer.as_ptr() as *const i8);
                    cstr.to_string_lossy().into_owned().into()
                } else {
                    None
                }
            }
        }
    }

    /// Get default log directory based on platform
    fn get_default_log_dir() -> Result<PathBuf> {
        #[cfg(windows)]
        {
            let appdata = std::env::var("USERPROFILE")
                .or_else(|_| std::env::var("APPDATA"))
                .context("Could not determine user directory")?;
            Ok(PathBuf::from(appdata).join("GitLogs"))
        }
        #[cfg(unix)]
        {
            let home = std::env::var("HOME").context("Could not determine home directory")?;
            Ok(PathBuf::from(home).join(".git-logs"))
        }
    }

    /// Detect available shells on the system
    fn detect_available_shells() -> Vec<String> {
        let mut shells = Vec::new();

        #[cfg(windows)]
        {
            // Check for PowerShell
            if Self::command_exists("powershell") {
                shells.push("powershell".to_string());
            }
            if Self::command_exists("pwsh") {
                shells.push("pwsh".to_string());
            }
        }

        #[cfg(unix)]
        {
            // Check for common shells
            let common_shells = ["bash", "zsh", "fish", "sh"];
            for shell in &common_shells {
                if Self::command_exists(shell) {
                    shells.push(shell.to_string());
                }
            }
        }

        if shells.is_empty() {
            // Fallback to at least one shell
            #[cfg(windows)]
            shells.push("cmd".to_string());
            #[cfg(unix)]
            shells.push("sh".to_string());
        }

        shells
    }

    /// Check if a command exists in PATH
    fn command_exists(command: &str) -> bool {
        #[cfg(windows)]
        {
            std::process::Command::new("where")
                .arg(command)
                .output()
                .map(|output| output.status.success())
                .unwrap_or(false)
        }
        #[cfg(unix)]
        {
            std::process::Command::new("which")
                .arg(command)
                .output()
                .map(|output| output.status.success())
                .unwrap_or(false)
        }
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<()> {
        if self.device_nickname.is_empty() {
            anyhow::bail!("Device nickname cannot be empty");
        }

        if self.enabled_shells.is_empty() {
            anyhow::bail!("At least one shell must be enabled");
        }

        if let Some(parent) = self.log_path.parent() {
            if !parent.exists() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("Failed to create log directory: {:?}", parent))?;
            }
        }

        if self.performance.max_memory_mb == 0 {
            anyhow::bail!("Max memory must be greater than 0");
        }

        if self.performance.log_buffer_size == 0 {
            anyhow::bail!("Log buffer size must be greater than 0");
        }

        Ok(())
    }
}
