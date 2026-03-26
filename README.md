# Git Command Monitor

A cross-platform background service that monitors and logs all git commands executed on a system, providing timestamped logs with repository context for debugging and tracking purposes.

## Features

- **Cross-platform**: Works on Windows and Linux
- **Low resource usage**: Target <10MB RAM, <0.1% CPU idle
- **Structured logging**: Format `timestamp|rootdir|command`
- **Command sanitization**: Removes sensitive information from logs
- **Log rotation**: Configurable file size limits and retention
- **Background service**: Runs as system service with auto-start

## Phase 1: Core Service (Current Implementation)

This release focuses on the foundational backend service:

### ✅ Implemented
- Core logging service with timestamp formatting
- Git command detection and parsing
- Git repository root finding
- Configuration management (JSON-based)
- Command sanitization (removes passwords, tokens)
- Log rotation and buffering
- Background daemon framework
- Cross-platform service structure

### 🔄 Next Phases
- **Phase 2**: Shell integration (PowerShell, bash, etc.)
- **Phase 3**: Installation system and UI
- **Phase 4**: Advanced features and monitoring

## Architecture

```
git-log-access/
├── src/
│   ├── main.rs              # CLI entry point
│   ├── lib.rs               # Library exports
│   ├── config/              # Configuration management
│   ├── monitor/             # Command parsing & detection
│   ├── service/             # Background service & logging
│   └── utils/               # Utilities (timestamp, git root)
├── config/                  # Default configuration
└── tests/                   # Integration tests
```

## Log Format

Each logged entry follows the format:
```
timestamp|rootdir|command
```

Example:
```
2026-03-26 14:32:15|C:\projects\myapp|git commit -m "fix user authentication"
2026-03-26 14:33:01|C:\projects\myapp|git push origin main
2026-03-26 14:45:22|/home/dev/webapp|git pull origin develop
```

## Usage

### Building

```bash
cargo build --release
```

### Running (Development/Testing)

```bash
# Run in foreground for testing
cargo run -- run --verbose

# Start as background service
cargo run -- start

# Check service status
cargo run -- status

# Stop service
cargo run -- stop
```

### Configuration

Create or modify configuration file:

```json
{
  "logPath": "C:\\GitLogs\\dev-laptop\\dev-laptop_githistory.log",
  "deviceNickname": "dev-laptop",
  "enabledShells": ["powershell", "cmd", "bash"],
  "monitorScope": "user",
  "logRotation": {
    "enabled": true,
    "maxSizeMb": 100,
    "keepFiles": 10
  },
  "performance": {
    "maxMemoryMb": 10,
    "logBufferSize": 1000,
    "flushIntervalSeconds": 30
  }
}
```

### Command Line Options

```
git-monitor [COMMAND]

Commands:
  start      Start the monitoring service
  stop       Stop the monitoring service
  install    Install as system service
  uninstall  Uninstall system service
  status     Show service status
  run        Run in foreground (for testing)
  help       Print this message or the help of the given subcommand(s)

Options:
  -h, --help     Print help
  -V, --version  Print version
```

## Performance Characteristics

### Resource Targets
- **Memory**: <10MB RAM usage
- **CPU**: <0.1% idle, <1% during active git usage
- **Disk I/O**: Batched writes, configurable flush intervals
- **Startup**: <2 seconds service initialization

### Optimization Features
- **Lazy loading**: Components loaded only when needed
- **Command filtering**: Early rejection of non-git commands
- **Buffered logging**: Reduces disk I/O with configurable batching
- **Efficient parsing**: Minimal string operations and allocations

## Security

### Privacy Protection
- **Local only**: No network transmission of data
- **Command sanitization**: Removes passwords, tokens, and sensitive args
- **User-controlled**: Configurable log location and retention
- **Minimal permissions**: Only requires access to shell and log directory

### Sanitized Arguments
The following sensitive arguments are automatically masked:
- `--password`, `--token`, `--credential`
- Git configuration with sensitive data
- Proxy settings and authentication

## Development

### Project Structure

- **`src/main.rs`**: CLI interface and service entry point
- **`src/config/`**: Configuration loading, validation, and defaults
- **`src/monitor/`**: Git command detection and parsing logic
- **`src/service/`**: Background daemon and logging service
- **`src/utils/`**: Shared utilities (timestamps, git root detection)

### Key Components

#### GitMonitorDaemon
The main service coordinator that:
- Manages service lifecycle
- Coordinates between parser and logger
- Handles background tasks and monitoring
- Provides statistics and status information

#### GitLogger
High-performance logging service with:
- Asynchronous buffered writing
- Configurable flush intervals
- Log rotation support
- Memory usage limits

#### GitCommandParser
Command parsing engine that:
- Detects git commands from various shells
- Sanitizes sensitive information
- Extracts repository context
- Supports command filtering

### Testing

```bash
# Run all tests
cargo test

# Run with output
cargo test -- --nocapture

# Test specific module
cargo test config::tests
```

### Dependencies

Core dependencies:
- **tokio**: Async runtime
- **serde**: Configuration serialization
- **chrono**: Timestamp formatting
- **anyhow**: Error handling
- **clap**: CLI argument parsing

## Roadmap

### Phase 2: Shell Integration
- PowerShell profile modification
- Bash/Zsh hook implementation
- Command Prompt integration
- WSL support
- Real-time command interception

### Phase 3: Installation & Management
- Windows MSI installer
- Linux package (.deb/.rpm)
- Service installation automation
- Configuration UI
- Uninstallation support

### Phase 4: Advanced Features
- Remote log aggregation
- Performance monitoring dashboard
- Advanced filtering and search
- Integration with development tools
- Analytics and reporting

## License

MIT License - see LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Support

For issues, questions, or contributions, please use the GitHub issue tracker.

## Changelog

### v0.1.0 (Phase 1)
- Initial core service implementation
- Basic git command monitoring
- Configuration system
- Logging service with rotation
- Cross-platform daemon framework