#!/usr/bin/env bash
# Git Monitor Binary Installation Script
# This script installs the pre-compiled binary (no compilation required)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/git-monitor}"
LOG_DIR="${LOG_DIR:-$HOME/.local/share/git-monitor}"
FORCE_INSTALL="${FORCE_INSTALL:-false}"
NO_SERVICE="${NO_SERVICE:-false}"
SILENT="${SILENT:-false}"

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

get_exe_path() {
    echo "$INSTALL_DIR/git-monitor"
}

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
  NO_SERVICE=true                # Skip automatic hook and daemon activation
  SILENT=true                    # Use defaults, no interactive prompts (skips reinstall)

Examples:
  INSTALL_DIR=~/.local/bin ./install.sh        # Install to user directory
  FORCE_INSTALL=true ./install.sh              # Overwrite existing install without prompt
  NO_SERVICE=true ./install.sh                 # Skip automatic activation
  SILENT=true ./install.sh                     # Automated install with defaults
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."

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

    if [ ! -f "git-monitor" ]; then
        log_error "git-monitor executable not found in current directory"
        echo "Please ensure you've extracted the binary distribution correctly"
        return 1
    fi

    log_success "Prerequisites check passed"
    return 0
}

install_executable() {
    log_info "Installing Git Monitor executable..."

    local target_path
    target_path="$(get_exe_path)"

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
            [ -f "$target_path" ] && echo "  Found at: $target_path"
            command -v git-monitor >/dev/null 2>&1 && echo "  Command available in PATH"
            echo "Use FORCE_INSTALL=true to overwrite in silent mode"
            return 1
        else
            log_warn "Git Monitor installation detected:"
            [ -f "$target_path" ] && echo "  Executable: $target_path"
            command -v git-monitor >/dev/null 2>&1 && echo "  Command available in PATH"
            echo ""
            while true; do
                printf "Do you want to reinstall? This will overwrite existing files. [y/N]: "
                read -r response
                response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

                case "$response" in
                    ""|n|no)
                        echo "Installation cancelled."
                        echo "Use FORCE_INSTALL=true to reinstall without prompting"
                        return 1
                        ;;
                    y|yes)
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

    if [ ! -w "$(dirname "$INSTALL_DIR")" ]; then
        log_warn "Need sudo access to install to $INSTALL_DIR"
        if sudo mkdir -p "$INSTALL_DIR" && sudo cp git-monitor "$target_path" && sudo chmod +x "$target_path"; then
            log_success "Installed executable to $target_path"
        else
            local alt_dir="$HOME/.local/bin"
            log_info "Trying alternative installation to $alt_dir..."
            mkdir -p "$alt_dir"
            if cp git-monitor "$alt_dir/git-monitor" && chmod +x "$alt_dir/git-monitor"; then
                log_success "Installed executable to $alt_dir/git-monitor"
                log_warn "Make sure $alt_dir is in your PATH"
                echo "Add this to your shell profile:"
                echo "export PATH=\"$alt_dir:\$PATH\""
                INSTALL_DIR="$alt_dir"
            else
                log_error "Failed to install executable"
                return 1
            fi
        fi
    else
        mkdir -p "$INSTALL_DIR"
        if cp git-monitor "$target_path" && chmod +x "$target_path"; then
            log_success "Installed executable to $target_path"
        else
            log_error "Failed to install executable"
            return 1
        fi
    fi

    if [ -f "git-monitor.json" ]; then
        cp git-monitor.json "$INSTALL_DIR/default-config.json" 2>/dev/null || true
        log_info "Copied default configuration"
    fi

    return 0
}

get_user_configuration() {
    if [ "$SILENT" = "true" ]; then
        local hostname
        hostname=$(hostname 2>/dev/null || echo "my-computer")
        echo "$hostname|$LOG_DIR|100"
        return 0
    fi

    echo ""
    echo -e "${BLUE}=== Git Monitor Configuration ===${NC}"
    echo "Please provide your preferences for Git Monitor setup"
    echo ""

    local default_nickname
    default_nickname=$(hostname 2>/dev/null || echo "my-computer")
    echo -e "${BLUE}Device Nickname:${NC}"
    echo "  This identifies your device in log entries"
    printf "Device nickname [%s]: " "$default_nickname"
    read -r device_nickname
    [ -z "$device_nickname" ] && device_nickname="$default_nickname"

    echo ""
    echo -e "${BLUE}Log Directory:${NC}"
    echo "  Where git command logs will be stored"
    printf "Log directory [%s]: " "$LOG_DIR"
    read -r log_dir
    [ -z "$log_dir" ] && log_dir="$LOG_DIR"
    log_dir="${log_dir/#\~/$HOME}"
    if [[ "$log_dir" != /* ]]; then
        log_dir="$(pwd)/$log_dir"
    fi

    echo ""
    echo -e "${BLUE}Log Rotation:${NC}"
    echo "  Automatically rotate logs when they get too large"
    printf "Maximum log file size in MB [100]: "
    read -r max_size_mb
    if [ -z "$max_size_mb" ] || ! [[ "$max_size_mb" =~ ^[0-9]+$ ]]; then
        max_size_mb=100
    fi

    echo ""
    echo -e "${GREEN}=== Configuration Summary ===${NC}"
    echo "Device Nickname: $device_nickname"
    echo "Log Directory: $log_dir"
    echo "Log File: $log_dir/${device_nickname}_githistory.log"
    echo "Max Log Size: ${max_size_mb}MB"
    echo ""
    printf "Continue with this configuration? [Y/n]: "
    read -r confirm
    if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
        log_warn "Configuration cancelled by user"
        return 1
    fi

    echo "$device_nickname|$log_dir|$max_size_mb"
    return 0
}

create_config() {
    log_info "Setting up configuration..."

    local config_result
    config_result=$(get_user_configuration) || return 1
    IFS='|' read -r device_nickname user_log_dir max_size_mb <<< "$config_result"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$user_log_dir"

    local config_path="$CONFIG_DIR/config.json"
    local log_file="$user_log_dir/${device_nickname}_githistory.log"

    if [ -f "$config_path" ] && [ "$FORCE_INSTALL" != "true" ]; then
        log_info "Configuration already exists at $config_path"
        return 0
    fi

    cat > "$config_path" << EOF
{
  "logPath": "$log_file",
  "deviceNickname": "$device_nickname",
  "enabledShells": ["bash", "zsh", "fish", "sh"],
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

test_installation() {
    log_info "Testing installation..."

    local git_monitor_cmd
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    elif [ -x "$(get_exe_path)" ]; then
        git_monitor_cmd="$(get_exe_path)"
    else
        log_error "git-monitor executable not found"
        return 1
    fi

    if $git_monitor_cmd --help > /dev/null 2>&1; then
        log_success "Executable test passed"
        return 0
    fi

    log_error "Executable test failed"
    return 1
}

enable_monitoring() {
    if [ "$NO_SERVICE" = "true" ]; then
        log_info "Skipping automatic monitor activation (NO_SERVICE=true)"
        log_info "You can enable hooks and the background monitor later with: git-monitor start"
        return 0
    fi

    log_info "Enabling shell hooks and background monitor..."

    local git_monitor_cmd
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    else
        git_monitor_cmd="$(get_exe_path)"
    fi

    if $git_monitor_cmd start > /dev/null 2>&1; then
        log_success "Monitoring enabled"
        log_info "Open a new shell so the installed profile hook is loaded"
    else
        log_warn "Automatic activation failed"
        log_info "You can enable it later with: git-monitor start"
    fi

    return 0
}

show_completion() {
    echo ""
    echo -e "${GREEN}=== Git Monitor Installation Complete ===${NC}"
    echo ""
    echo "Git Monitor has been successfully installed."
    echo ""

    if [ "$NO_SERVICE" = "true" ]; then
        echo -e "${YELLOW}Monitoring has not been enabled yet.${NC}"
        echo "Run 'git-monitor start' when you are ready to install hooks and start the daemon."
    else
        echo -e "${GREEN}Hook-based interception and the background monitor were enabled.${NC}"
        echo "Open a new shell so the installed profile hook is loaded."
    fi

    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  Open a new terminal so PATH and shell profile changes are picked up"
    echo "  Run git-monitor status to confirm interception and daemon state"
    echo "  Run a few git commands in a repository and inspect your log file"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  git-monitor start            # Enable hooks and start the background monitor"
    echo "  git-monitor stop             # Disable hooks and stop the background monitor"
    echo "  git-monitor status           # Show hook and daemon status"
    echo "  git-monitor run --verbose    # Foreground smoke test"
    echo "  git-monitor --help           # Full command list"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  Edit: $CONFIG_DIR/config.json"
    echo ""
    echo -e "${BLUE}Getting Help:${NC}"
    echo "  https://github.com/bengreynolds/git-log-access"
    echo ""
}

uninstall() {
    log_info "Uninstalling Git Monitor..."

    local git_monitor_cmd=""
    if command -v git-monitor &> /dev/null; then
        git_monitor_cmd="git-monitor"
    elif [ -x "$(get_exe_path)" ]; then
        git_monitor_cmd="$(get_exe_path)"
    fi

    if [ -n "$git_monitor_cmd" ]; then
        $git_monitor_cmd stop > /dev/null 2>&1 || true
        $git_monitor_cmd uninstall > /dev/null 2>&1 || true
    fi

    local target_path
    target_path="$(get_exe_path)"
    if [ -f "$target_path" ]; then
        if [ -w "$(dirname "$target_path")" ]; then
            rm -f "$target_path"
        else
            sudo rm -f "$target_path"
        fi
        log_success "Removed executable"
    fi

    echo ""
    read -p "Remove configuration and log files? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR" 2>/dev/null || true
        rm -rf "$LOG_DIR" 2>/dev/null || true
        log_success "Removed user data"
    fi

    log_success "Uninstallation complete"
}

main() {
    echo -e "${BLUE}Git Monitor Binary Installer${NC}"
    echo "============================="
    echo ""

    check_prerequisites || exit 1
    install_executable || exit 1
    create_config || exit 1
    test_installation || exit 1
    enable_monitoring
    show_completion
}

case "${1:-install}" in
    install|"")
        main
        ;;
    uninstall|remove)
        uninstall
        ;;
    --help|-h|help)
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
