#!/usr/bin/env bash
# Installation Requirements Test Script
# Tests all dependencies and requirements for Git Monitor installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Log function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((FAILED_TESTS++))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

# Test functions
test_rust_toolchain() {
    echo "Testing Rust toolchain..."
    
    # Test cargo
    if command -v cargo &> /dev/null; then
        local cargo_version=$(cargo --version)
        log_pass "Cargo found: $cargo_version"
        
        # Test minimum version (1.70+)
        local version_num=$(echo "$cargo_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ "$version_num" ]]; then
            local major=$(echo "$version_num" | cut -d. -f1)
            local minor=$(echo "$version_num" | cut -d. -f2)
            if [[ $major -gt 1 ]] || [[ $major -eq 1 && $minor -ge 70 ]]; then
                log_pass "Rust version is compatible (>= 1.70)"
            else
                log_error "Rust version too old. Need 1.70 or higher, found $version_num"
                echo "  Fix: Update Rust with 'rustup update'"
            fi
        fi
    else
        log_error "Cargo not found"
        echo "  Fix: Install Rust from https://rustup.rs/"
        echo "       curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    fi

    # Test rustc
    if command -v rustc &> /dev/null; then
        local rustc_version=$(rustc --version)
        log_pass "Rust compiler found: $rustc_version"
    else
        log_error "Rust compiler (rustc) not found"
        echo "  Fix: Install Rust from https://rustup.rs/"
    fi
}

test_git_installation() {
    echo "Testing Git installation..."
    
    if command -v git &> /dev/null; then
        local git_version=$(git --version)
        log_pass "Git found: $git_version"
        
        # Test git functionality
        if git config --global user.name &> /dev/null; then
            log_pass "Git is configured"
        else
            log_warn "Git user not configured"
            echo "  Recommendation: Configure git with:"
            echo "    git config --global user.name 'Your Name'"
            echo "    git config --global user.email 'your.email@example.com'"
        fi
    else
        log_error "Git not found"
        case "$OSTYPE" in
            linux*)
                echo "  Fix: Install git:"
                echo "    Ubuntu/Debian: sudo apt install git"
                echo "    RHEL/CentOS: sudo yum install git"
                echo "    Arch: sudo pacman -S git"
                ;;
            darwin*)
                echo "  Fix: Install git:"
                echo "    brew install git"
                echo "    Or install Xcode Command Line Tools"
                ;;
            msys*|cygwin*)
                echo "  Fix: Install git:"
                echo "    Download from https://git-scm.com/download/win"
                echo "    Or use winget: winget install Git.Git"
                ;;
            *)
                echo "  Fix: Install git for your platform from https://git-scm.com/"
                ;;
        esac
    fi
}

test_permissions() {
    echo "Testing file system permissions..."
    
    # Test current directory write permissions
    local test_file="./test_write_permissions.tmp"
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        log_pass "Current directory is writable"
    else
        log_error "Cannot write to current directory"
        echo "  Fix: Ensure you have write permissions to $(pwd)"
    fi
    
    # Test log directory creation (use default from config)
    local log_dir
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        log_dir="C:/GitLogs/test"
    else
        log_dir="$HOME/.config/git-monitor/test"
    fi
    
    echo "Testing log directory creation at: $log_dir"
    if mkdir -p "$log_dir" 2>/dev/null; then
        if touch "$log_dir/test.log" 2>/dev/null; then
            rm -f "$log_dir/test.log"
            rmdir "$log_dir" 2>/dev/null || true
            log_pass "Can create and write to log directory"
        else
            log_error "Cannot write to log directory: $log_dir"
            echo "  Fix: Ensure write permissions to the log directory"
        fi
    else
        log_error "Cannot create log directory: $log_dir"
        echo "  Fix: Ensure write permissions to parent directory"
    fi
}

test_platform_specific() {
    echo "Testing platform-specific requirements..."
    
    case "$OSTYPE" in
        linux*)
            test_linux_requirements
            ;;
        darwin*)
            test_macos_requirements
            ;;
        msys*|cygwin*)
            test_windows_requirements
            ;;
        *)
            log_warn "Unknown platform: $OSTYPE"
            echo "  This may work but is untested"
            ;;
    esac
}

test_linux_requirements() {
    # Test systemd (for service management)
    if command -v systemctl &> /dev/null; then
        log_pass "systemd found (for service management)"
    else
        log_warn "systemd not found"
        echo "  Note: Service installation may not work on this system"
        echo "  Alternative: Run manually or use cron for startup"
    fi
    
    # Test shells
    local shells_found=0
    for shell in bash zsh fish; do
        if command -v "$shell" &> /dev/null; then
            log_pass "Shell found: $shell"
            ((shells_found++))
        fi
    done
    
    if [[ $shells_found -eq 0 ]]; then
        log_error "No supported shells found (bash, zsh, fish)"
        echo "  Fix: Install at least one supported shell"
    fi
    
    # Test if we can write to /etc/systemd/system (for service installation)
    if [[ -w "/etc/systemd/system" ]] 2>/dev/null; then
        log_pass "Can install system services"
    else
        log_warn "Cannot write to /etc/systemd/system"
        echo "  Note: Will need sudo for service installation"
    fi
}

test_windows_requirements() {
    # Test PowerShell
    if command -v powershell &> /dev/null || command -v pwsh &> /dev/null; then
        log_pass "PowerShell found"
    else
        log_error "PowerShell not found"
        echo "  Fix: Install PowerShell from https://github.com/PowerShell/PowerShell"
    fi
    
    # Test if running as administrator (for service installation)
    # This is approximated in bash/msys environment
    log_warn "Windows service installation requires administrator privileges"
    echo "  Note: Run installer as Administrator for service installation"
    
    # Test Windows Service support (approximated)
    if command -v sc &> /dev/null; then
        log_pass "Windows Service Control Manager accessible"
    else
        log_warn "Cannot access Windows Service Control Manager"
    fi
}

test_macos_requirements() {
    # Test if we can use launchd for services
    if [[ -d "/Library/LaunchDaemons" ]]; then
        log_pass "macOS LaunchDaemon support available"
    else
        log_warn "Cannot access LaunchDaemon directory"
        echo "  Note: May need sudo for service installation"
    fi
    
    # Test basic shells
    for shell in bash zsh; do
        if command -v "$shell" &> /dev/null; then
            log_pass "Shell found: $shell"
        fi
    done
}

test_network_requirements() {
    echo "Testing network requirements..."
    
    # We don't need network for core functionality
    log_pass "No network requirements (local operation only)"
    
    # But test internet for crate dependencies during build
    if ping -c 1 crates.io &> /dev/null 2>&1; then
        log_pass "Internet connectivity (needed for Rust dependencies)"
    else
        log_warn "No internet connectivity"
        echo "  Note: Internet required for initial build (Rust crates)"
        echo "  Fix: Ensure internet access or use offline build"
    fi
}

test_build_requirements() {
    echo "Testing build requirements..."
    
    # Test if we can compile a basic Rust project
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    if cargo init test-project --name test 2>/dev/null; then
        cd test-project
        if cargo check 2>/dev/null; then
            log_pass "Rust compilation works"
        else
            log_error "Rust compilation failed"
            echo "  Fix: Check Rust installation or try: rustup update"
        fi
    else
        log_error "Cannot create test Rust project"
    fi
    
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Main execution
main() {
    echo "Git Monitor - Installation Requirements Test"
    echo "=============================================="
    echo ""
    
    test_rust_toolchain
    echo ""
    
    test_git_installation
    echo ""
    
    test_permissions
    echo ""
    
    test_platform_specific
    echo ""
    
    test_network_requirements
    echo ""
    
    test_build_requirements
    echo ""
    
    # Summary
    echo "=============================================="
    echo "Test Summary:"
    echo -e "  ${GREEN}Passed: $PASSED_TESTS${NC}"
    
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
    fi
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "  ${RED}Failed: $FAILED_TESTS${NC}"
        echo ""
        echo -e "${RED}Installation requirements not met!${NC}"
        echo "Please fix the failed tests before proceeding with installation."
        exit 1
    else
        echo ""
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}Installation requirements mostly satisfied with warnings.${NC}"
            echo "You may proceed, but some features might not work optimally."
        else
            echo -e "${GREEN}All installation requirements satisfied!${NC}"
            echo "Ready to proceed with installation."
        fi
        exit 0
    fi
}

# Run tests
main "$@"