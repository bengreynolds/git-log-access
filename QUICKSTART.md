# Quick Install Guide

## Status: Hook-Based Interception Ready

The project builds, passes its tests, and now supports real git interception through shell hooks. The current implementation manages per-user shell integration rather than a true OS background service.

## One-Command Install

### Windows (PowerShell):
```powershell
# 1. Download the release bundle
# 2. Run the bundled installer script
.\scripts\install-binary.ps1

# 3. Install hooks and start monitoring
git-monitor start
```

### Linux/macOS:
```bash
# 1. Download the release bundle
# 2. Run the bundled installer script
./scripts/install-binary.sh

# 3. Install hooks and start monitoring
git-monitor start
```

## What You Get

- Compiled executable (`git-monitor.exe` on Windows)
- Default configuration
- Per-user shell hook installation for supported shells
- Start/stop/status lifecycle for hook-based interception and background monitoring

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
- Ready: background process monitoring plus hook-based interception

Next step: build the project, run `git-monitor start`, restart your shell if needed, and verify `git` commands appear in the configured log.
