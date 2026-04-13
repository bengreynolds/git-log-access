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

Recommended install: use the release bundle for your platform.

That path installs the prebuilt executable and configures the normal hook/startup flow without requiring you to compile anything.

### Windows Release Install

Run the installer that ships with the release bundle:

```powershell
scripts\install-binary.ps1
```

Or, if you prefer batch:

```powershell
scripts\install-binary.bat
```

After installation:

```powershell
git-monitor status
git-monitor start
```

### Linux/macOS Release Install

Run the shell installer that ships with the release bundle:

```bash
./scripts/install-binary.sh
git-monitor status
git-monitor start
```

## Installation Paths

### Build From Source

This is for contributors and developers who want to build the binary themselves.

1. Clone the repository.
2. Install Rust 1.70 or newer.
3. Run `cargo build --release`.
4. Use `cargo run -- run --verbose` to test.

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
- If the release installer fails, rerun it with verbose output and check the generated install log.
- If you are building from source and the binary does not start, run `cargo run -- --help` or `git-monitor --help` to verify the binary starts.

## Development

```powershell
cargo test
cargo clippy
cargo fmt
```

The repository also includes `QUICKSTART.md` for a shorter install summary.
