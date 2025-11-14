# eGPU Auto-Enable 🚀

**Automatically re-enable your eGPU after hot-plugging on Windows**

Never manually enable your eGPU from Device Manager again! This tool monitors your external GPU and automatically enables it whenever you reconnect it after safe-removal.

[![PowerShell](https://img.shields.io/badge/PowerShell-7.0+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)

---

## 🎯 Problem

When using an external GPU (eGPU) via Thunderbolt/USB-C on Windows:
1. You "safely remove" it using NVIDIA Control Panel (or Device Manager)
2. You physically disconnect the eGPU
3. When you plug it back in... **it stays disabled** 😤
4. You have to manually open Device Manager and enable it every time

## ✨ Solution

This tool runs silently in the background and:
- ✅ Detects when you safe-remove your eGPU
- ✅ Waits for you to unplug and replug it
- ✅ **Automatically enables it** when reconnected!
- ✅ Logs all activity with automatic rotation (max 500 KB)

---

## 🚀 Quick Install

### One-Line Install (Recommended)

Run this command in **PowerShell as Administrator**:

```powershell
irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex
```

### Manual Install

1. **Download both files:**
   - [Install-eGPU-Startup.ps1](https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1)
   - [eGPU.ps1](https://raw.githubusercontent.com/Bananz0/eGPUae/main/eGPU.ps1)

2. **Run the installer as Administrator:**
   ```powershell
   .\Install-eGPU-Startup.ps1
   ```

3. **Select your eGPU from the list**

4. **Done!** It will start automatically on every boot.

---

## 📋 Requirements

- **Windows 10/11**
- **PowerShell 7+** ([Download here](https://github.com/PowerShell/PowerShell/releases))
- **Administrator privileges** (needed to enable/disable devices)
- **An external GPU** connected via Thunderbolt or USB-C

---

## 🎮 How to Use

### Your New Workflow:

1. **Safe-remove your eGPU**
   - Use NVIDIA Control Panel → "Safely remove GPU"
   - Or Device Manager → Right-click GPU → Disable

2. **Physically unplug the eGPU**
   - Disconnect the Thunderbolt/USB-C cable

3. **Do whatever you need to do** 🎉

4. **Plug the eGPU back in**
   - The script automatically detects it and enables it!
   - No manual intervention needed!

### Monitor States:

The script tracks your eGPU through three states:
- **✓ present-ok** - eGPU is connected and working
- **⊗ present-disabled** - eGPU is safe-removed (waiting for unplug)
- **○ absent** - eGPU is physically unplugged

---

## 🛠️ Commands

### View Live Monitor (for testing)
```powershell
pwsh "$env:USERPROFILE\.egpu-manager\eGPU.ps1"
```

### Start Background Task
```powershell
Start-ScheduledTask -TaskName "eGPU-AutoEnable"
```

### Stop Background Task
```powershell
Stop-ScheduledTask -TaskName "eGPU-AutoEnable"
```

### Reconfigure (Change eGPU)
```powershell
irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex
# Choose option [1] Reconfigure
```

### Uninstall
```powershell
# Download and run with -Uninstall flag
irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 -OutFile "$env:TEMP\Install-eGPU-Startup.ps1"
pwsh "$env:TEMP\Install-eGPU-Startup.ps1" -Uninstall
```

Or if you have the file locally:
```powershell
.\Install-eGPU-Startup.ps1 -Uninstall
```

---

## 📁 Installation Details

### Files Created:
```
C:\Users\YourName\.egpu-manager\
├── eGPU.ps1              # Monitor script
└── egpu-config.json      # Your eGPU configuration
```

### Scheduled Task:
- **Name:** `eGPU-AutoEnable`
- **Trigger:** At system startup (10 second delay)
- **Runs as:** Your user account with elevated privileges
- **Hidden:** Yes (runs silently in background)

---

## 🔧 How It Works

1. **Monitoring:** The script polls your eGPU status every 2 seconds
2. **Detection:** It detects state changes:
   - Safe-removal via NVIDIA Control Panel
   - Physical disconnection
   - Physical reconnection
3. **Auto-Enable:** When reconnected while disabled, it uses `pnputil /enable-device` (the same command Windows Device Manager uses internally)
4. **Verification:** Confirms the device is actually working after enabling

### Technical Details:
- Uses `Get-PnpDevice` to query device state
- Tracks transitions between `present-ok`, `present-disabled`, and `absent`
- Only triggers auto-enable after a full unplug/replug cycle (not just on disable)
- Uses `pnputil.exe` for maximum reliability (same as Device Manager)

---

## ❓ FAQ

### Q: Will this work with AMD GPUs?
**A:** Yes! The script works with any external GPU. Just select your eGPU during installation.

### Q: Does it work with laptops?
**A:** Yes, as long as you have Thunderbolt or USB-C with eGPU support.

### Q: What if I have multiple eGPUs?
**A:** Currently supports one eGPU. For multiple eGPUs, you can modify the config or run multiple instances with different configs.

### Q: Does it slow down my system?
**A:** No. It only polls every 2 seconds and uses minimal resources. The task runs hidden in the background.

### Q: Can I disable it temporarily?
**A:** Yes:
```powershell
Stop-ScheduledTask -TaskName "eGPU-AutoEnable"
```
To re-enable:
```powershell
Start-ScheduledTask -TaskName "eGPU-AutoEnable"
```

### Q: What if it doesn't work?
**A:** 
1. Make sure you're running PowerShell as Administrator
2. Check Task Scheduler to see if the task exists
3. Try running the monitor manually to see error messages:
   ```powershell
   pwsh "$env:USERPROFILE\.egpu-manager\eGPU.ps1"
   ```
4. Open an [issue on GitHub](https://github.com/Bananz0/eGPUae/issues)

---

## 🐛 Troubleshooting

### "Script must be run as Administrator"
- Right-click PowerShell → "Run as Administrator"

### "Execution policy" error
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### eGPU not detected during installation
- Make sure your eGPU is plugged in and working
- Check Device Manager → Display adapters to see if Windows recognizes it

### Auto-enable isn't working
1. Check if the task is running:
   ```powershell
   Get-ScheduledTask -TaskName "eGPU-AutoEnable"
   ```
2. View task history in Task Scheduler (`taskschd.msc`)
3. Run the monitor manually to see live output

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

---

## 📜 License

MIT License - feel free to use, modify, and distribute!

---

## 🙏 Credits

Created to solve the annoying eGPU hot-plug workflow on Windows.

Inspired by the frustration of opening Device Manager every single time 😅

---

## ⭐ Star This Repo!

If this tool saved you time, consider giving it a star! ⭐

It helps others discover this solution and motivates further development.

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/Bananz0/eGPUae/issues)
- **Discussions:** [GitHub Discussions](https://github.com/Bananz0/eGPUae/discussions)

---

**Made with ❤️ for the eGPU community**