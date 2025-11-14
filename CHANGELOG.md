# Changelog

All notable changes to eGPU Auto-Enable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-11-14

### Added
- **Automatic display sleep management** - Disables monitor sleep when eGPU is connected with external displays, restores original settings when unplugged
- External monitor detection to intelligently manage display sleep
- Improved Windows toast notifications compatibility for PowerShell 7

### Fixed
- Toast notifications now work correctly in PowerShell 7 (fixed WinRT assembly loading)
- Better error handling for display sleep management

### Changed
- Version bump to 1.1.0
- Enhanced logging for display sleep operations

---

## [1.0.0] - 2025-11-14

### Added
- Initial release of eGPU Auto-Enable
- Automatic eGPU re-enabling after hot-plug
- Interactive installer with GPU detection and selection
- Scheduled task creation for startup automation
- Configuration file system (JSON-based)
- State monitoring: `present-ok`, `present-disabled`, `absent`
- Uses `pnputil` for reliable device enabling
- Uninstall functionality
- Reconfigure option to change selected eGPU
- Heartbeat monitoring (every 30 seconds)
- Clean state transitions and user-friendly console output
- One-line remote installation support
- Comprehensive README with troubleshooting guide
- **Automatic logging with rotation** (max 500 KB, keeps last 1000 lines)
- Log backup system (keeps previous log as `.old.log`)
- **Windows Toast Notifications** for eGPU enable/disable events
- **Update notifications** (checks once per day, non-intrusive)
- Automatic script download from GitHub during installation

### Technical Details
- Poll interval: 2 seconds
- Installation location: `%USERPROFILE%\.egpu-manager\`
- Scheduled task: `eGPU-AutoEnable`
- Startup delay: 10 seconds
- Requires PowerShell 7+ and Administrator privileges

### Known Issues
- Single eGPU support only (multi-eGPU planned for future)
- Windows 10/11 only

---

## [Unreleased]

### Planned Features
- Multi-eGPU support
- Custom poll interval configuration
- System tray icon for easy control
- Statistics tracking (reconnection count, uptime)
- Configurable log rotation settings
- Option to disable notifications

---

## Version History

- **1.0.0** (2025-11-14) - Initial release