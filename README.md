# Git Command Monitor

Git Monitor is a Rust tool that logs git commands with repository context and supports hook-based interception through shell profiles.

## Current Status

- The project builds and passes tests
- Real git interception is available through shell hooks
- `install`, `start`, `stop`, `status`, and `uninstall` manage the hook-based workflow
- The background process monitor exists, but shell hooks provide the most accurate repository context on Windows

## What It Records

Git Monitor writes entries in this format:

```text
timestamp=2026-03-26T14:32:15.123Z :: repo=C:\projects\myapp :: command=git commit -m "fix user authentication"
```

Sensitive values are sanitized before they are written.

## Start Here

Install Rust if needed, then build the project:

```powershell
cargo build --release
```

Run the monitor in foreground mode for testing:

```powershell
cargo run -- run --verbose
```

If you have a release bundle, run the included installer script for your platform and then start the monitor:

```powershell
git-monitor start
git-monitor status
```

## Installation Paths

### Build From Source

1. Clone the repository.
2. Install Rust 1.70 or newer.
3. Run `cargo build --release`.
4. Use `cargo run -- run --verbose` to test.

### Release Bundle

1. Download the release archive for your platform.
2. Run the platform installer that ships with the bundle or, from this repo, use one of:
   - `scripts/install-binary.ps1`
   - `scripts/install-binary.bat`
   - `scripts/install-binary.sh`
3. Run `git-monitor start` to enable interception.

## Configuration

The tool uses a JSON configuration file.

Common settings:

- `logPath` - where git command logs are written
- `deviceNickname` - identifier used in log entries
- `enabledShells` - shells to monitor
- `monitorScope` - user or system
- `logRotation` - rotation size and retention

Typical config locations:

- Windows user install: `%APPDATA%\git-monitor\config.json`
- Windows system install: `%PROGRAMDATA%\GitMonitor\config.json`
- Linux/macOS user install: `~/.config/git-monitor/config.json`
- Linux/macOS system install: `/etc/git-monitor/config.json`

## Service Commands

```powershell
git-monitor start
git-monitor stop
git-monitor status
git-monitor run --verbose
git-monitor uninstall
```

`install` writes shell hook blocks into supported profiles. `capture` is an internal subcommand invoked by those hooks when you run `git`.

## Troubleshooting

- If git commands are not being logged, confirm `git-monitor status` reports interception as enabled.
- If the tool cannot find your config, check the installation output for the exact config path.
- If the install script fails, run `cargo run -- --help` or `git-monitor --help` to verify the binary starts.

## Development

```powershell
cargo test
cargo clippy
cargo fmt
```

The repository also includes `QUICKSTART.md` for a shorter install summary.
