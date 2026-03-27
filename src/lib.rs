//! Git Log Access - Cross-platform git command monitoring service
//!
//! This library provides functionality to monitor and log git commands
//! across different platforms with minimal resource usage.

pub mod config;
pub mod monitor;
pub mod service;
pub mod utils;

use anyhow::Result;

/// Main application error type
pub type AppResult<T> = Result<T>;

/// Version information
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Default configuration
pub const DEFAULT_CONFIG_NAME: &str = "config.json";
pub const DEFAULT_LOG_NAME: &str = "githistory.log";

/// Performance targets
pub const MAX_MEMORY_MB: u64 = 10;
pub const TARGET_CPU_IDLE_PERCENT: f32 = 0.1;

/// Log format specification: timestamp=... :: repo=... :: command=...
pub const LOG_FORMAT_SEPARATOR: &str = " :: ";
pub const LOG_TIMESTAMP_PREFIX: &str = "timestamp=";
pub const LOG_REPO_PREFIX: &str = "repo=";
pub const LOG_COMMAND_PREFIX: &str = "command=";
pub const LEGACY_LOG_FORMAT_SEPARATOR: &str = "|";
