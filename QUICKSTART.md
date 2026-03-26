# Quick Install Guide

## Status: Hook-Based Interception Ready

The project builds, passes its tests, and now supports real git interception through shell hooks. The current implementation manages per-user shell integration rather than a true OS background service.

## One-Command Install

### Windows (PowerShell):
```powershell
# 1. Install Rust
winget install Rustlang.Rust.MSVC

# 2. Restart terminal, then install Git Monitor
.\install.ps1

# 3. Install hooks and enable interception
git-monitor install
```

### Linux/macOS:
```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# 2. Install Git Monitor
./install.sh

# 3. Install hooks and enable interception
git-monitor install
```

## What You Get

- Compiled executable (`git-monitor.exe` on Windows)
- Default configuration
- Per-user shell hook installation for supported shells
- Start/stop/status lifecycle for hook-based interception

## Quick Test After Install

```bash
# Show interception status
git-monitor status

# Run a git command in a supported shell
git status

# Check the configured log file
```

## Current Scope

- Ready: parser, logger, hook manager, and lifecycle commands
- Ready: real git interception through shell profile hooks
- Pending: true OS service management and process-table interception

Next step: build the project, run `git-monitor install`, restart your shell if needed, and verify `git` commands appear in the configured log.
