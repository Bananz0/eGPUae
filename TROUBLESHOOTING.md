# Troubleshooting Guide

Quick solutions to common issues with eGPU Auto-Enable.

---

## Installation Issues

### "Script must be run as Administrator"
**Solution:** Right-click PowerShell → "Run as Administrator"

### "Execution policy" error
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
Then run the installer again.

### eGPU not detected during installation
1. Make sure your eGPU is plugged in and powered on
2. Check Device Manager → Display adapters
3. Ensure NVIDIA/AMD drivers are installed
4. Try replugging the eGPU and running the installer again

---

## Runtime Issues

### Auto-enable isn't working

**Check if the task is running:**
```powershell
Get-ScheduledTask -TaskName "eGPU-AutoEnable" | Select-Object State
```

**Start the task manually:**
```powershell
Start-ScheduledTask -TaskName "eGPU-AutoEnable"
```

**Check the logs:**
```powershell
Get-Content "$env:USERPROFILE\.egpu-manager\egpu-manager.log" -Tail 100
```

**Run the monitor manually to see live output:**
```powershell
pwsh "$env:USERPROFILE\.egpu-manager\eGPU.ps1"
```

### eGPU enables but immediately disables

This could be a driver or power issue:
1. Update your GPU drivers to the latest version
2. Check Thunderbolt firmware is up to date
3. Verify eGPU enclosure has adequate power
4. Check Windows Event Viewer for device errors

### Script stops running after some time

**Check Task Scheduler history:**
1. Open Task Scheduler (`taskschd.msc`)
2. Navigate to Task Scheduler Library
3. Find "eGPU-AutoEnable"
4. Click "History" tab at bottom
5. Look for errors or unexpected stops

**Restart the task:**
```powershell
Stop-ScheduledTask -TaskName "eGPU-AutoEnable"
Start-ScheduledTask -TaskName "eGPU-AutoEnable"
```

### Wrong GPU is being monitored

**Reconfigure to select correct GPU:**
```powershell
irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex
```
Choose option [1] Reconfigure

---

## Log Issues

### Log file is too large

The log should auto-rotate at 500 KB. If it's larger:
1. Check if the script is running (it rotates logs automatically)
2. Manually delete the log:
   ```powershell
   Remove-Item "$env:USERPROFILE\.egpu-manager\egpu-manager.log" -Force
   ```

### Can't find log file

**Check installation directory:**
```powershell
explorer "$env:USERPROFILE\.egpu-manager"
```

**Verify installation:**
```powershell
Test-Path "$env:USERPROFILE\.egpu-manager\eGPU.ps1"
```

---

## Performance Issues

### High CPU usage

The script polls every 2 seconds and should use minimal CPU. If you see high usage:
1. Check Task Manager for the `pwsh.exe` process
2. Review logs for excessive error messages
3. Consider increasing poll interval (requires modifying script)

### Script slowing down system startup

The script has a 10-second delay at startup. If still causing issues:
1. Open Task Scheduler (`taskschd.msc`)
2. Find "eGPU-AutoEnable"
3. Right-click → Properties
4. Go to Triggers tab
5. Edit the trigger and increase delay (e.g., 30 seconds)

---

## Uninstallation Issues

### Can't remove scheduled task

```powershell
# Force remove as Administrator
Unregister-ScheduledTask -TaskName "eGPU-AutoEnable" -Confirm:$false
```

### Installation folder won't delete

The script may still be running:
```powershell
# Stop the task first
Stop-ScheduledTask -TaskName "eGPU-AutoEnable"

# Wait a moment
Start-Sleep -Seconds 3

# Try deleting again
Remove-Item "$env:USERPROFILE\.egpu-manager" -Recurse -Force
```

If still locked, restart Windows and try again.

---

## Advanced Debugging

### Enable verbose console output

Run the script manually to see all output:
```powershell
pwsh "$env:USERPROFILE\.egpu-manager\eGPU.ps1"
```

### Check device state manually

```powershell
# List all display adapters
Get-PnpDevice -Class Display | Format-Table FriendlyName, Status, InstanceId

# Check specific GPU
Get-PnpDevice | Where-Object {$_.FriendlyName -like "*RTX*"}
```

### Test pnputil manually

```powershell
# Get your eGPU's Instance ID from Device Manager
$instanceId = "YOUR_INSTANCE_ID_HERE"

# Try enabling manually
pnputil /enable-device "$instanceId"
```

### Check PowerShell version

```powershell
$PSVersionTable.PSVersion
```
Should be 7.0 or higher. [Download PowerShell 7+](https://github.com/PowerShell/PowerShell/releases)

---

## Still Having Issues?

1. **Check existing issues:** [GitHub Issues](https://github.com/Bananz0/eGPUae/issues)
2. **Open a new issue** with:
   - Your Windows version
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - eGPU model and enclosure
   - Last 50 lines of log file
   - Any error messages you see

3. **Join the discussion:** [GitHub Discussions](https://github.com/Bananz0/eGPUae/discussions)

---

## Common Workarounds

### eGPU takes too long to enable

Increase the stabilization delay in the script:
1. Open `$env:USERPROFILE\.egpu-manager\eGPU.ps1`
2. Find line: `Start-Sleep -Seconds 2`
3. Change to: `Start-Sleep -Seconds 5`
4. Restart the task

### Script conflicts with other software

Some GPU management software may conflict:
- NVIDIA GeForce Experience
- MSI Afterburner
- GPU Tweak II

Try temporarily disabling these to test.

---

**Last Updated:** 2025-11-14