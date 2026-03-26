# Quick Install Guide

## Status: Prototype

The project builds and the Rust test suite passes, but the monitoring pipeline is not complete yet. The current `run` command is useful for exercising log output, not for capturing real git commands from your shell.

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

- Compiled executable (`git-monitor.exe` on Windows)
- Default configuration
- Log writer and parser scaffold
- Demo foreground mode for validating log output

## Quick Test After Install

```bash
# Run demo mode
git-monitor run --verbose

# The current foreground mode emits demo git commands for validation.
# Check the logs (path shown during install).
```

## Installation Scripts

- `install.ps1` - Windows PowerShell installer
- `install.sh` - Linux/macOS bash installer
- `scripts/test-requirements.*` - Check prerequisites

Both installers:
- Check prerequisites
- Build optimized release binary
- Install to PATH
- Create default config
- Test installation
- Show usage instructions that mark the current placeholders clearly

## Current Status

- Missing: Rust toolchain
- Ready: Buildable codebase with passing tests
- Pending: Shell integration and real service lifecycle support

Next step: install Rust, build the project, and use `git-monitor run --verbose` only as a demo/logging check.
