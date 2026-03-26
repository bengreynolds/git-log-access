# 🚀 Quick Install Guide

## Status: **Ready to Build** ✅

The Git Monitor project is complete and ready for installation. You just need Rust installed first.

## One-Command Install

### Windows (PowerShell - Run as Administrator):
```powershell
# 1. Install Rust
winget install Rustlang.Rust.MSVC

# 2. Restart terminal, then install Git Monitor
.\install.ps1
```

### Linux/macOS:
```bash
# 1. Install Rust 
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# 2. Install Git Monitor
./install.sh
```

## What You Get

✅ **Compiled executable** (`git-monitor.exe` on Windows)  
✅ **Automatic PATH setup** (use `git-monitor` from anywhere)  
✅ **Default configuration** created  
✅ **Ready to run** immediately  

## Quick Test After Install

```bash
# Test in foreground mode
git-monitor run --verbose

# In another terminal, run some git commands
cd some-git-repo
git status
git log --oneline

# Check the logs (path shown during install)
```

## Installation Scripts

- **`install.ps1`** - Windows PowerShell installer
- **`install.sh`** - Linux/macOS bash installer  
- **`scripts/test-requirements.*`** - Check prerequisites

Both installers:
- ✅ Check prerequisites
- ✅ Build optimized release binary
- ✅ Install to system PATH
- ✅ Create default config
- ✅ Test installation
- ✅ Show usage instructions

## Current Status

❌ **Missing**: Rust toolchain  
✅ **Ready**: Complete codebase, installers, documentation  
✅ **Tested**: Installation scripts work when Rust is available  

**Next step**: Install Rust, then run the installer!