#!/usr/bin/env bash
# Git Monitor Binary Installation Script
# This script installs the pre-compiled binary (no compilation required)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/git-monitor}"
LOG_DIR="${LOG_DIR:-$HOME/.local/share/git-monitor}"
FORCE_INSTALL="${FORCE_INSTALL:-false}"
NO_SERVICE="${NO_SERVICE:-false}"
SILENT="${SILENT:-false}"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
show_usage() {
    cat << EOF
Git Monitor Binary Installer

Usage:
  ./install.sh [install]         # Install Git Monitor (prompts for reinstall if exists)
  ./install.sh uninstall         # Remove Git Monitor
  ./install.sh --help            # Show this help

Environment Variables:
  INSTALL_DIR=/path              # Installation directory (default: /usr/local/bin)
  CONFIG_DIR=/path               # Configuration directory (default: ~/.config/git-monitor)
  LOG_DIR=/path                  # Log directory (default: ~/.local/share/git-monitor)
  FORCE_INSTALL=true             # Force overwrite existing installation without prompting
  NO_SERVICE=true                # Skip service installation
  SILENT=true                    # Use defaults, no interactive prompts (skips reinstall)

Examples:
  INSTALL_DIR=~/.local/bin ./install.sh        # Install to user directory  
  FORCE_INSTALL=true ./install.sh              # Overwrite existing install without prompt
  NO_SERVICE=true ./install.sh                 # Skip service setup
  SILENT=true ./install.sh                     # Automated install with defaults
EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for git
    if ! command -v git &> /dev/null; then
        log_error "Git not found"
        case "$OSTYPE" in
            linux*)
                echo "  Install: sudo apt install git  (Ubuntu/Debian)"
                echo "           sudo yum install git  (RHEL/CentOS)"
                echo "           sudo pacman -S git   (Arch)"
                ;;
            darwin*)
                echo "  Install: brew install git"
                echo "           Or install Xcode Command Line Tools"
                ;;
            *)
                echo "  Install git for your platform"
                ;;
        esac
        return 1
    fi
    
    # Check that we have the executable
    if [ ! -f "git-monitor" ]; then
        log_error "git-monitor executable not found in current directory"
        echo "Please ensure you've extracted the binary distribution correctly"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Install the executable
install_executable() {
    log_info "Installing Git Monitor executable..."
    
    local target_path="$INSTALL_DIR/git-monitor"
    
    # Handle existing installation
    if [ -f "$target_path" ] || command -v git-monitor >/dev/null 2>&1; then
        if [ "$FORCE_INSTALL" = "true" ]; then
            if [ -f "$target_path" ]; then
                log_warn "Overwriting existing installation at $target_path"
            fi
            if command -v git-monitor >/dev/null 2>&1; then
                log_warn "Git Monitor command found in PATH"
            fi
        elif [ "$SILENT" = "true" ]; then
            log_error "Git Monitor already installed"
            if [ -f "$target_path" ]; then
                echo "  Found at: $target_path"
            fi
            if command -v git-monitor >/dev/null 2>&1; then
                echo "  Command available in PATH"
            fi
            echo "Use FORCE_INSTALL=true to overwrite in silent mode"
            return 1
        else
            log_warn "Git Monitor installation detected:"
            if [ -f "$target_path" ]; then
                echo "  Executable: $target_path"
            fi
            if command -v git-monitor >/dev/null 2>&1; then
                echo "  Command available in PATH"
            fi
            echo ""
            while true; do
                printf "Do you want to reinstall? This will overwrite existing files. [y/N]: "
                read -r response
                response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
                
                case "$response" in
                    ""|"|no|n)
                        echo "Installation cancelled."
                        echo "Use FORCE_INSTALL=true to reinstall without prompting"
                        return 1
                        ;;
                    yes|y)
                        log_info "Proceeding with reinstallation..."
                        FORCE_INSTALL="true"
                        break
                        ;;
                    *)
                        echo "Please enter 'y' for yes or 'n' for no."
                        ;;
                esac
            done
        fi
    fi
    
    # Check if we need sudo for installation directory
    if [ ! -w "$(dirname "$INSTALL_DIR")" ]; then
        log_warn "Need sudo access to install to $INSTALL_DIR"
        if sudo cp git-monitor "$target_path" && sudo chmod +x "$target_path"; then
            log_success "Installed executable to $target_path"
        else
            log_error "Failed to install executable with sudo"
            
            # Offer alternative installation
            local alt_dir="$HOME/.local/bin"
            log_info "Trying alternative installation to $alt_dir..."
            mkdir -p "$alt_dir"
            
            if cp git-monitor "$alt_dir/git-monitor" && chmod +x "$alt_dir/git-monitor"; then
                log_success "Installed executable to $alt_dir/git-monitor"
                log_warn "Make sure $alt_dir is in your PATH"
                echo "Add this to your ~/.bashrc or ~/.zshrc:"
                echo "export PATH=\"$alt_dir:\$PATH\""
                INSTALL_DIR="$alt_dir"
            else
                log_error "Failed to install executable"
                return 1
            fi
        fi
    else
        if cp git-monitor "$target_path" && chmod +x "$target_path"; then
            log_success "Installed executable to $target_path"
        else
            log_error "Failed to install executable"
            return 1
        fi
    fi
    
    # Copy default config if provided
    if [ -f "git-monitor.json" ]; then
        mkdir -p "$(dirname "$target_path")"
        cp git-monitor.json "$(dirname "$target_path")/default-config.json" 2>/dev/null || true
        log_info "Copied default configuration"
    fi
    
    return 0
}

# Get user configuration preferences
get_user_configuration() {
    # Use defaults for silent installation
    if [ "$SILENT" = "true" ]; then
        local hostname=$(hostname 2>/dev/null || echo "my-computer")
        echo "$hostname|$LOG_DIR|100"
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}=== Git Monitor Configuration ===${NC}"
    echo -e "${NC}Please provide your preferences for Git Monitor setup${NC}"
    echo ""
    
    # Device nickname
    local default_nickname=$(hostname 2>/dev/null || echo "my-computer")
    echo -e "${BLUE}Device Nickname:${NC}"
    echo -e "${NC}  This identifies your device in log entries${NC}"
    echo -n "Device nickname [$default_nickname]: "
    read device_nickname
    if [ -z "$device_nickname" ]; then
        device_nickname="$default_nickname"
    fi
    
    # Log directory
    local default_log_dir="$LOG_DIR"
    echo ""
    echo -e "${BLUE}Log Directory:${NC}"
    echo -e "${NC}  Where git command logs will be stored${NC}"
    echo -n "Log directory [$default_log_dir]: "
    read log_dir
    if [ -z "$log_dir" ]; then
        log_dir="$default_log_dir"
    fi
    
    # Expand ~ to home directory
    log_dir="${log_dir/#\~/$HOME}"
    
    # Convert to absolute path if relative
    if [[ "$log_dir" != /* ]]; then
        log_dir="$(pwd)/$log_dir"
    fi
    
    # Log rotation settings
    echo ""
    echo -e "${BLUE}Log Rotation:${NC}"
    echo -e "${NC}  Automatically rotate logs when they get too large${NC}"
    echo -n "Maximum log file size in MB [100]: "
    read max_size_mb
    if [ -z "$max_size_mb" ] || ! [[ "$max_size_mb" =~ ^[0-9]+$ ]]; then
        max_size_mb=100
    fi
    
    # Confirmation
    echo ""
    echo -e "${GREEN}=== Configuration Summary ===${NC}"
    echo -e "${NC}Device Nickname: $device_nickname${NC}"
    echo -e "${NC}Log Directory: $log_dir${NC}"
    echo -e "${NC}Log File: $log_dir/${device_nickname}_githistory.log${NC}"
    echo -e "${NC}Max Log Size: ${max_size_mb}MB${NC}"
    echo ""
    
    echo -n "Continue with this configuration? [Y/n]: "
    read confirm
    if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
        log_warn "Configuration cancelled by user"
        return 1
    fi
    
    echo "$device_nickname|$log_dir|$max_size_mb"
    return 0
}

# Create user configuration
create_config() {
    log_info "Setting up configuration..."
    
    # Get user preferences
    local config_result
    config_result=$(get_user_configuration)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Parse the result
    IFS='|' read -r device_nickname user_log_dir max_size_mb <<< "$config_result"
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$user_log_dir"
    
    local config_path="$CONFIG_DIR/config.json"
    local log_file="$user_log_dir/${device_nickname}_githistory.log"
    
    # Don't overwrite existing config unless forced
    if [ -f "$config_path" ] && [ "$FORCE_INSTALL" != "true" ]; then
        log_info "Configuration already exists at $config_path"
        return 0
    fi
    
    # Create config
    cat > "$config_path" << EOF
{
  "logPath": "$log_file",
  "deviceNickname": "$device_nickname",
  "enabledShells": ["bash", "zsh", "fish"],
  "monitorScope": "user",
  "logRotation": {
    "enabled": true,
    "maxSizeMb": $max_size_mb,
    "keepFiles": 10
  },
  "performance": {
    "maxMemoryMb": 10,
    "logBufferSize": 1000,
    "flushIntervalSeconds": 30
  }
}
EOF
    
    log_success "Created configuration at $config_path"
    log_success "Log will be written to: $log_file"
    
    return 0
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Test executable
    local git_monitor_cmd
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    elif [ -x "$INSTALL_DIR/git-monitor" ]; then
        git_monitor_cmd="$INSTALL_DIR/git-monitor"
    else
        log_error "git-monitor executable not found in PATH"
        return 1
    fi
    
    # Test basic functionality
    if $git_monitor_cmd --help > /dev/null 2>&1; then
        log_success "Executable test passed"
    else
        log_error "Executable test failed"
        return 1
    fi
    
    return 0
}

# Install as service
install_service() {
    if [ "$NO_SERVICE" = "true" ]; then
        log_info "Skipping service installation (NO_SERVICE=true)"
        return 0
    fi
    
    log_info "Setting up Git Monitor as system service..."
    
    local git_monitor_cmd
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    else
        git_monitor_cmd="$INSTALL_DIR/git-monitor"
    fi
    
    case "$OSTYPE" in
        linux*)
            # SystemD service
            if command -v systemctl &> /dev/null; then
                log_info "Installing systemd service..."
                if $git_monitor_cmd install 2>/dev/null; then
                    log_success "Service installed successfully"
                    
                    # Enable and start the service
                    log_info "Enabling auto-start and starting service..."
                    if sudo systemctl enable git-monitor 2>/dev/null && sudo systemctl start git-monitor 2>/dev/null; then
                        log_success "✅ Git Monitor service started and enabled for auto-start"
                    else
                        log_warn "Service installed but failed to start automatically"
                        log_info "You can start it with: sudo systemctl start git-monitor"
                    fi
                else
                    log_warn "Service installation failed"
                    log_info "You can still use manual mode: git-monitor run"
                fi
            else
                log_warn "SystemD not available - manual startup required"
                log_info "Run: git-monitor run"
            fi
            ;;
        darwin*)
            # macOS LaunchAgent
            log_info "Installing macOS LaunchAgent..."
            if $git_monitor_cmd install 2>/dev/null; then
                log_success "LaunchAgent installed successfully"
                
                # Start the service immediately
                log_info "Starting Git Monitor service..."
                if $git_monitor_cmd start 2>/dev/null; then
                    log_success "✅ Git Monitor service started and will auto-start on login"
                else
                    log_warn "LaunchAgent installed but failed to start"
                    log_info "You can start it with: git-monitor start"
                fi
            else
                log_warn "LaunchAgent installation failed"
                log_info "You can still use manual mode: git-monitor run"
            fi
            ;;
        *)
            log_warn "Unknown platform - manual startup required"
            log_info "Run: git-monitor run"
            ;;
    esac
    
    return 0
}

# Show completion message
show_completion() {
    echo ""
    echo -e "${GREEN}=== Git Monitor Installation Complete ===${NC}"
    echo ""
    echo "Git Monitor has been successfully installed!"
    echo ""
    echo -e "${BLUE}Quick Start:${NC}"
    echo "  1. Test: git-monitor run --verbose"
    echo "  2. Run some git commands in another terminal"
    echo "  3. Check your log file for entries"
    echo "  4. When ready: git-monitor start (if service installed)"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  git-monitor run --verbose    # Test in foreground"
    echo "  git-monitor status           # Check service status"
    echo "  git-monitor start/stop       # Control service"
    echo "  git-monitor --help           # Full command list"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  Edit: $CONFIG_DIR/config.json"
    echo ""
    echo -e "${BLUE}Getting Help:${NC}"
    echo "  https://github.com/bengreynolds/git-log-access"
    echo ""
}

# Uninstall function
uninstall() {
    log_info "Uninstalling Git Monitor..."
    
    local git_monitor_cmd
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    elif [ -x "$INSTALL_DIR/git-monitor" ]; then
        git_monitor_cmd="$INSTALL_DIR/git-monitor"
    fi
    
    # Stop and remove service if it exists
    if [ -n "$git_monitor_cmd" ]; then
        $git_monitor_cmd stop 2>/dev/null || true
        $git_monitor_cmd uninstall 2>/dev/null || true
    fi
    
    # Remove executable
    local target_path="$INSTALL_DIR/git-monitor"
    if [ -f "$target_path" ]; then
        if [ -w "$(dirname "$target_path")" ]; then
            rm -f "$target_path"
        else
            sudo rm -f "$target_path"
        fi
        log_success "Removed executable"
    fi
    
    # Option to remove config and logs
    echo ""
    read -p "Remove configuration and log files? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR" 2>/dev/null || true
        rm -rf "$LOG_DIR" 2>/dev/null || true
        log_success "Removed user data"
    fi
    
    log_success "Uninstallation complete"
}

# Main installation process
main() {
    echo -e "${BLUE}Git Monitor Binary Installer${NC}"
    echo "============================="
    echo ""
    
    if ! check_prerequisites; then
        exit 1
    fi
    
    if ! install_executable; then
        exit 1
    fi
    
    if ! create_config; then
        exit 1
    fi
    
    if ! test_installation; then
        exit 1
    fi
    
    install_service
    show_completion
}

# Parse command line arguments
case "${1:-install}" in
    "install"|"")
        main
        ;;
    "uninstall"|"remove")
        uninstall
        ;;
    "--help"|"-h"|"help")
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac