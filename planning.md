# Git Command Monitor - Project Planning

## Overview
A cross-platform background service that monitors and logs all git commands executed on a system, providing timestamped logs with repository context for debugging and tracking purposes.

## Log Format
Each logged entry follows the format: `timestamp|rootdir|command`

Example:
```
2026-03-26 14:32:15|C:\projects\myapp|git commit -m "fix user authentication"
2026-03-26 14:33:01|C:\projects\myapp|git push origin main
2026-03-26 14:45:22|/home/dev/webapp|git pull origin develop
```

## Architecture

### Core Components

1. **Shell Hook Module**
   - Intercepts shell command execution
   - Filters for git commands only
   - Minimal processing overhead

2. **Command Parser**
   - Extracts relevant git commands
   - Determines repository root directory
   - Formats timestamp and context

3. **Logger Service**
   - Writes to configured log file
   - Handles file rotation if needed
   - Ensures atomic writes

4. **Background Daemon**
   - Runs continuously as system service
   - Auto-starts on boot
   - Minimal resource consumption

### Cross-Platform Implementation

#### Windows
- **Service**: Windows Service (using `windows-service`)
- **Shell Hooking**: 
  - PowerShell: Profile modification + command history
  - Command Prompt: DOSKEY macros or process monitoring
  - WSL: Linux approach within WSL environment
- **Auto-start**: Service Control Manager
- **Installation**: MSI installer or PowerShell script

#### Linux
- **Service**: systemd service
- **Shell Hooking**:
  - Bash: PROMPT_COMMAND or trap on DEBUG
  - Zsh: preexec hook
  - Fish: event handlers
- **Auto-start**: systemd enable
- **Installation**: Package manager or installer script

### Monitoring Approaches

#### Option A: Shell Integration (Preferred)
- Modify shell profiles to run git commands through wrapper
- Lightweight, shell-specific implementation
- Direct command interception

#### Option B: Process Monitoring
- Monitor system processes for git execution
- Higher resource usage but more universal
- May miss embedded git commands

#### Option C: LD_PRELOAD / DLL Injection (Advanced)
- Intercept system calls
- Most comprehensive but complex
- Requires elevated privileges

## Installation Process

### User Configuration Options

1. **Installation Directory**
   - Default Windows: `C:\Program Files\GitLogMonitor`
   - Default Linux: `/opt/gitlogmonitor` or `/usr/local/bin`
   - User customizable path

2. **Log File Location**
   - Default: User-specified parent directory
   - Structure: `<parent>/<device_nickname>/<device_nickname>_githistory.log`
   - Example: `C:\GitLogs\dev-laptop\dev-laptop_githistory.log`

3. **Device Nickname**
   - User-friendly identifier for the machine
   - Used in directory structure and log identification
   - Default: hostname, customizable

4. **Platform Selection**
   - Windows: PowerShell, CMD, WSL
   - Linux: Bash, Zsh, Fish
   - IDE Integration: VSCode, others

5. **Monitoring Scope**
   - System-wide (all users)
   - Current user only
   - Specific directories/repositories

### Installation Flow

1. **Welcome & License Agreement**
2. **Installation Path Selection**
3. **Log Configuration**
   - Parent directory selection
   - Device nickname input
   - Log rotation settings
4. **Platform Selection**
   - Available shell environments
   - IDE integration options
5. **Service Installation**
   - Register system service
   - Configure auto-start
6. **Shell Integration Setup**
   - Modify shell profiles
   - Install shell hooks
7. **Verification & Testing**
   - Test git command logging
   - Verify service status

## Technical Implementation Strategy

### Phase 1: Core Service
- Implement basic logging service
- Create cross-platform service wrapper
- Establish log file format and management

### Phase 2: Shell Integration
- Develop shell-specific hooks
- Implement command interception
- Test across different shell environments

### Phase 3: Installation System
- Create installer packages
- Implement configuration UI
- Add uninstallation support

### Phase 4: Advanced Features
- Log rotation and compression
- Remote log aggregation
- Performance monitoring dashboard

## Performance Optimization

### Resource Minimization
- **Memory**: Target <10MB RAM usage
- **CPU**: <0.1% during idle, <1% during active git usage
- **Disk I/O**: Batched logging, async writes
- **Network**: None (local logging only)

### Optimization Strategies
1. **Lazy Loading**: Load components only when needed
2. **Command Filtering**: Early rejection of non-git commands
3. **Efficient Logging**: Buffered writes, minimal formatting
4. **Smart Monitoring**: Hook only when terminals are active
5. **Resource Throttling**: Limit log frequency if needed

## Security Considerations

### Permissions
- Minimal required privileges
- Read-only access to shell environments
- Write access only to designated log directory

### Data Protection
- Local storage only (no network transmission)
- User-controlled log location
- Configurable log retention

### Privacy
- Log only git commands (no arguments with sensitive data)
- Optional command sanitization
- Clear data collection disclosure

## Configuration Management

### Config File Format (JSON/YAML)
```json
{
  "logPath": "C:\\GitLogs\\dev-laptop\\dev-laptop_githistory.log",
  "deviceNickname": "dev-laptop",
  "enabledShells": ["powershell", "cmd", "bash"],
  "monitorScope": "user",
  "logRotation": {
    "enabled": true,
    "maxSizeMB": 100,
    "keepFiles": 10
  },
  "performance": {
    "maxMemoryMB": 10,
    "logBufferSize": 1000
  }
}
```

### Runtime Configuration
- Service reload without restart
- Log level adjustment
- Temporary disable/enable
- Real-time monitoring stats

## Testing Strategy

### Unit Tests
- Command parsing accuracy
- Log formatting validation
- Configuration management
- Cross-platform compatibility

### Integration Tests
- Shell hook functionality
- Service lifecycle management
- Multi-shell environment testing
- Log file operations

### Performance Tests
- Resource usage measurement
- Stress testing with high git activity
- Memory leak detection
- Service stability over time

## Deployment Considerations

### Package Distribution
- **Windows**: MSI installer, chocolatey package
- **Linux**: .deb, .rpm, snap package
- **Cross-platform**: Standalone executables

### Update Mechanism
- Automatic update checking
- Seamless service updates
- Configuration preservation
- Rollback capability

## Success Criteria

1. **Functionality**: Accurately logs all git commands with proper context
2. **Performance**: <10MB RAM, <0.1% CPU idle usage
3. **Reliability**: 99.9% uptime, no missed commands
4. **Compatibility**: Works on target shell environments
5. **Usability**: Simple installation and configuration process