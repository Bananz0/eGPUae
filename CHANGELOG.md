# Changelog

All notable changes to eGPU Auto-Enable will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-11-14

### Added
- **Custom eGPU High Performance power plan** - Automatically created during install with maximum performance settings (CPU 100%, PCIe max power, USB no suspend)
- **Automatic power plan switching** - Switches to eGPU plan when connected, restores original when disconnected
- **Laptop lid close action management** - Sets to "Do Nothing" when eGPU connected, restores user preference when disconnected
- **User power preference configuration** during installation:
  - Display timeout duration (minutes or system default)
  - Lid close action preference (Do Nothing/Sleep/Hibernate/Shut Down)
- **Crash recovery system** - Automatically restores settings if script terminates unexpectedly
- **Runtime state persistence** (runtime-state.json) - Saves original power settings for recovery
- **Smart restore logic** - Distinguishes between reboots and crashes to prevent false restorations
- **CIM-based lid close management** - More reliable than powercfg, works across all Windows configurations
- Notifications for all power management events

### Changed
- **BREAKING:** Installer now requires user input for power management preferences
- Enhanced installer with power management configuration section
- Power plan cleanup during uninstall (removes custom eGPU plan)
- Config file now includes: DisplayTimeoutMinutes, LidCloseActionAC, eGPUPowerPlanGuid
- Improved state transition handling for all disconnect scenarios (safe-remove and direct unplug)
- Version bump to 2.0.0 (major feature release)

### Fixed
- Settings now restore correctly on both safe-removal and direct unplug
- Lid close action management now uses reliable CIM classes (Win32_PowerSettingDataIndex)
- User preferences always take priority over saved values during restoration
- Power plan restoration works in all disconnect scenarios

### Technical Details
- Uses Windows CIM classes (root\cimv2\power) for reliable power setting management
- Source attribution: CIM method based on https://superuser.com/a/1700937 (CC BY-SA 4.0)
- Lid action values: 0=DoNothing, 1=Sleep, 2=Hibernate, 3=ShutDown
- Runtime state cleared on clean exits and when eGPU present at startup

---

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

## Planned Features (Roadmap)

Here's a look at what's planned for future versions:

-   **System Tray Icon:** Add an icon to the system tray for quick status view and manual controls (e.g., "Enable/Disable", "Pause Monitoring").
-   **Multi-eGPU Support:** Allow the tool to configure and manage multiple eGPUs independently.
-   **Application Auto-Launch:** Provide an option to launch specific applications (e.g., Steam, Adobe Premiere) when the eGPU is successfully enabled.
-   **Statistics Dashboard:** Track and display usage statistics (e.g., reconnection count, uptime, successful auto-enable rate).
-   **Scheduled eGPU Enable/Disable:** Add time-based automation for enabling or disabling the eGPU.
-   **Customizable Notifications:** Allow users to set custom notification sounds for success/failure events.
-   **Project Branding:** Create a custom logo for the project.