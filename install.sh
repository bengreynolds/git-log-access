#!/usr/bin/env bash
# Git Monitor Simple Installation Script
# This script will build and install Git Monitor as an executable

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/git-monitor"
SERVICE_NAME="git-monitor"

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

# Check if running on macOS and adjust install directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    INSTALL_DIR="/usr/local/bin"
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for Rust/cargo
    if ! command -v cargo &> /dev/null; then
        log_error "Rust/cargo not found"
        echo "Please install Rust from https://rustup.rs/"
        echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
    
    # Check for git
    if ! command -v git &> /dev/null; then
        log_error "Git not found"
        echo "Please install git for your platform"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to build the project
build_project() {
    log_info "Building Git Monitor..."
    
    # Clean previous builds
    if [ -d "target" ]; then
        log_info "Cleaning previous build..."
        cargo clean
    fi
    
    # Build release version
    log_info "Compiling release version (this may take a few minutes)..."
    if cargo build --release; then
        log_success "Build completed successfully"
    else
        log_error "Build failed"
        echo "Check the error messages above and ensure all dependencies are available"
        exit 1
    fi
    
    # Verify the executable exists
    if [ ! -f "target/release/git-monitor" ]; then
        log_error "Built executable not found at target/release/git-monitor"
        exit 1
    fi
}

# Function to install the executable
install_executable() {
    local target_path="$INSTALL_DIR/git-monitor"
    
    log_info "Installing executable to $target_path..."
    
    # Check if we need sudo
    if [ ! -w "$INSTALL_DIR" ]; then
        log_warn "Need sudo access to install to $INSTALL_DIR"
        if sudo cp target/release/git-monitor "$target_path"; then
            sudo chmod +x "$target_path"
            log_success "Installed executable to $target_path"
        else
            log_error "Failed to install executable"
            
            # Offer alternative installation
            local alt_dir="$HOME/.local/bin"
            log_info "Trying alternative installation to $alt_dir..."
            mkdir -p "$alt_dir"
            
            if cp target/release/git-monitor "$alt_dir/git-monitor"; then
                chmod +x "$alt_dir/git-monitor"
                log_success "Installed executable to $alt_dir/git-monitor"
                log_warn "Make sure $alt_dir is in your PATH"
                echo "Add this to your ~/.bashrc or ~/.zshrc:"
                echo "export PATH=\"$alt_dir:\$PATH\""
                INSTALL_DIR="$alt_dir"
            else
                log_error "Failed to install executable"
                exit 1
            fi
        fi
    else
        if cp target/release/git-monitor "$target_path"; then
            chmod +x "$target_path"
            log_success "Installed executable to $target_path"
        else
            log_error "Failed to install executable"
            exit 1
        fi
    fi
}

# Function to create default configuration
create_config() {
    log_info "Creating default configuration..."
    
    mkdir -p "$CONFIG_DIR"
    
    # Get hostname for device nickname
    local hostname=$(hostname || echo "unknown")
    local log_dir="$HOME/.local/share/git-monitor"
    
    # Create log directory
    mkdir -p "$log_dir"
    
    # Create default config
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "logPath": "$log_dir/${hostname}_githistory.log",
  "deviceNickname": "$hostname",
  "enabledShells": ["bash", "zsh", "fish"],
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
EOF
    
    log_success "Created configuration at $CONFIG_DIR/config.json"
    log_info "Log will be written to: $log_dir/${hostname}_githistory.log"
}

# Function to test installation
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
    if $git_monitor_cmd --help > /dev/null; then
        log_success "Executable test passed"
    else
        log_error "Executable test failed"
        return 1
    fi
    
    # Test configuration loading
    if $git_monitor_cmd status > /dev/null 2>&1; then
        log_success "Configuration test passed"
    else
        log_info "Service not running (this is normal for first install)"
    fi
}

# Function to provide usage instructions
show_usage_instructions() {
    echo ""
    echo -e "${GREEN}=== Installation Complete ===${NC}"
    echo ""
    echo "Git Monitor has been successfully installed!"
    echo ""
    echo -e "${BLUE}Basic Usage:${NC}"
    echo "  git-monitor run --verbose    # Run in foreground for testing"
    echo "  git-monitor status           # Check service status"
    echo "  git-monitor start            # Start background service"
    echo "  git-monitor stop             # Stop background service"
    echo "  git-monitor install          # Install as system service"
    echo ""
    echo -e "${BLUE}Configuration:${NC}"
    echo "  Config file: $CONFIG_DIR/config.json"
    echo "  Edit this file to customize logging behavior"
    echo ""
    echo -e "${BLUE}Quick Start:${NC}"
    echo "  1. Test: git-monitor run --verbose"
    echo "  2. Run some git commands in another terminal"
    echo "  3. Check your log file for entries"
    echo "  4. When ready: git-monitor install && git-monitor start"
    echo ""
    echo -e "${BLUE}Getting Help:${NC}"
    echo "  git-monitor --help           # Show all commands"
    echo "  https://github.com/bengreynolds/git-log-access"
    echo ""
}

# Main installation process
main() {
    echo -e "${BLUE}Git Monitor - Simple Installation${NC}"
    echo "=================================="
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "Cargo.toml" ] || [ ! -f "src/main.rs" ]; then
        log_error "Please run this script from the git-log-access project directory"
        echo "Expected files: Cargo.toml, src/main.rs"
        exit 1
    fi
    
    # Run installation steps
    check_prerequisites
    build_project
    install_executable
    create_config
    test_installation
    show_usage_instructions
}

# Parse command line arguments
case "${1:-install}" in
    "install")
        main
        ;;
    "build-only")
        check_prerequisites
        build_project
        log_success "Build complete. Run './install.sh install' to install."
        ;;
    "test")
        # Run the requirements test
        if [ -f "scripts/test-requirements.sh" ]; then
            bash scripts/test-requirements.sh
        else
            log_error "Requirements test script not found"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 [install|build-only|test]"
        echo "  install     - Full installation (default)"
        echo "  build-only  - Just compile the project"
        echo "  test        - Run requirements test"
        exit 1
        ;;
esac