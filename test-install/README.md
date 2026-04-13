# Git Monitor Test Install

This folder is a sample installation layout used to validate the packaged Git Monitor installer.

It is not the main documentation for the app. For normal usage, read the parent repository README.

## Purpose

- Verify that the installer can place files in a self-contained install directory
- Exercise the Windows install and uninstall flow
- Provide a simple reference configuration for testing

## Contents

- `install.ps1`
- `install.bat`
- `git-monitor.json`
- `QUICKSTART.md`

## How To Use

1. Open this folder.
2. Run the platform-specific install script.
3. Confirm the generated install directory matches the expected test layout.
4. Use the bundled config only for validation, not as a production configuration.

## Notes

- This folder exists for installer testing and packaging checks.
- The active project docs live in `git-log-access/README.md` and `git-log-access/QUICKSTART.md`.
