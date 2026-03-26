use super::Config;
use anyhow::Result;
use std::path::Path;

impl Config {
    /// Create a configuration for testing purposes
    pub fn test_config() -> Self {
        use std::env;
        
        let temp_dir = env::temp_dir().join("git-monitor-test");
        
        Config {
            log_path: temp_dir.join("test_githistory.log"),
            device_nickname: "test-device".to_string(),
            enabled_shells: vec!["bash".to_string()],
            monitor_scope: "user".to_string(),
            log_rotation: super::LogRotationConfig {
                enabled: false, // Disable for tests
                max_size_mb: 1,
                keep_files: 1,
            },
            performance: super::PerformanceConfig {
                max_memory_mb: 5,
                log_buffer_size: 10, // Small buffer for tests
                flush_interval_seconds: 1, // Fast flush for tests
            },
        }
    }

    /// Create configuration with custom log path
    pub fn with_log_path<P: AsRef<Path>>(mut self, path: P) -> Self {
        self.log_path = path.as_ref().to_path_buf();
        let filename = format!("{}_githistory.log", self.device_nickname);
        if self.log_path.is_dir() {
            self.log_path = self.log_path.join(filename);
        }
        self
    }

    /// Create configuration with custom device nickname
    pub fn with_device_nickname<S: Into<String>>(mut self, nickname: S) -> Self {
        self.device_nickname = nickname.into();
        self
    }

    /// Enable specific shells only
    pub fn with_shells(mut self, shells: Vec<String>) -> Self {
        self.enabled_shells = shells;
        self
    }

    /// Set monitoring scope
    pub fn with_scope<S: Into<String>>(mut self, scope: S) -> Self {
        self.monitor_scope = scope.into();
        self
    }
}