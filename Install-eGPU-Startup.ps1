# eGPU Auto-Enable Installer/Uninstaller
# Interactive setup for automatic eGPU re-enabling at startup

# VERSION CONSTANT - Update this when releasing new versions
$SCRIPT_VERSION = "2.3.0"

<#
.SYNOPSIS
    eGPU Auto-Enable Tool - Automatically re-enables eGPU after hot-plugging on Windows

.DESCRIPTION
    This tool monitors your external GPU and automatically enables it whenever you reconnect it after safe-removal.
    It eliminates the need to manually enable the eGPU from Device Manager.

.PARAMETER Uninstall
    Removes the eGPU Auto-Enable tool from your system.

.EXAMPLE
    .\Install-eGPU-Startup.ps1
    Installs the eGPU Auto-Enable tool with interactive configuration.

.EXAMPLE
    .\Install-eGPU-Startup.ps1 -Uninstall
    Removes the eGPU Auto-Enable tool from your system.

.EXAMPLE
    irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex
    Installs the eGPU Auto-Enable tool in one line.

.NOTES
    File Name      : Install-eGPU-Startup.ps1
    Prerequisite   : PowerShell 7.0 or later
    Requires Admin : Yes
    Version        : 2.2.0
    Repository     : https://github.com/Bananz0/eGPUae
#>

param(
    [switch]$Uninstall
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    pause
    exit
}

$taskName = "eGPU-AutoEnable"
$installPath = Join-Path $env:USERPROFILE ".egpu-manager"
$monitorScriptPath = Join-Path $installPath "eGPU.ps1"
$configPath = Join-Path $installPath "egpu-config.json"

# ==================== UNINSTALL MODE ====================
if ($Uninstall) {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  eGPU Auto-Enable UNINSTALLER" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    
    Write-Host "This will remove:" -ForegroundColor Yellow
    Write-Host "  • Scheduled task: $taskName" -ForegroundColor Gray
    Write-Host "  • Installation folder: $installPath" -ForegroundColor Gray
    Write-Host ""
    
    $confirm = Read-Host "Are you sure you want to uninstall? (Y/N)"
    
    if ($confirm -notlike "y*") {
        Write-Host "`nUninstall cancelled." -ForegroundColor Yellow
        pause
        exit
    }
    
    Write-Host "`nUninstalling..." -ForegroundColor Yellow
    
    # Stop any running instances of the script
    $runningProcesses = Get-Process | Where-Object { $_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*" }
    if ($runningProcesses) {
        Write-Host "  Stopping running eGPU monitor processes..." -ForegroundColor Gray
        $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    
    # Remove scheduled task
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "  Removing scheduled task..." -ForegroundColor Gray
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "  ✓ Task removed" -ForegroundColor Green
    }
    else {
        Write-Host "  • Task not found (already removed)" -ForegroundColor DarkGray
    }
    
    # Remove installation folder
    if (Test-Path $installPath) {
        Write-Host "  Removing installation folder..." -ForegroundColor Gray
        
        # Check for eGPU power plan in config before deleting
        $configPath = Join-Path $installPath "egpu-config.json"
        if (Test-Path $configPath) {
            try {
                $config = Get-Content $configPath | ConvertFrom-Json
                if ($config.PSObject.Properties.Name -contains 'eGPUPowerPlanGuid' -and $config.eGPUPowerPlanGuid) {
                    Write-Host "  Removing eGPU power plan..." -ForegroundColor Gray
                    powercfg -delete $config.eGPUPowerPlanGuid 2>&1 | Out-Null
                    Write-Host "  ✓ Power plan removed" -ForegroundColor Green
                }
            }
            catch {
                Write-Error "Failed to read or process config during uninstall: $_"
            }
        }
        
        try {
            Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Folder removed" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ Could not remove folder automatically" -ForegroundColor Yellow
            Write-Host "  Please manually delete: $installPath" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  • Folder not found (already removed)" -ForegroundColor DarkGray
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Uninstall Complete!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    Write-Host "eGPU Auto-Enable has been removed from your system." -ForegroundColor White
    Write-Host "You will need to manually enable your eGPU from Device Manager after reconnecting.`n" -ForegroundColor Gray
    
    pause
    exit
}

# ==================== INSTALL MODE ====================
Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  eGPU Auto-Enable INSTALLER" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Installation location: $installPath`n" -ForegroundColor Gray

# Check if already installed
$alreadyInstalled = (Test-Path $installPath) -or (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)

if ($alreadyInstalled) {
    Write-Host "⚠ eGPU Auto-Enable is already installed!" -ForegroundColor Yellow
    
    # Check current version
    $currentVersion = "Unknown"
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath | ConvertFrom-Json
            $currentVersion = if ($config.InstalledVersion) { $config.InstalledVersion } else { "1.0.0" }
        }
        catch {
            Write-Error "Failed to read version from config: $_"
        }
    }
    Write-Host "Current version: $currentVersion" -ForegroundColor Gray
    Write-Host "Installer version: $SCRIPT_VERSION" -ForegroundColor Gray
    
    Write-Host "`nWhat would you like to do?" -ForegroundColor Cyan
    Write-Host "  [1] Update (download and install latest version)" -ForegroundColor Gray
    Write-Host "  [2] Reconfigure (change settings/eGPU)" -ForegroundColor Gray
    Write-Host "  [3] Reinstall (fresh installation)" -ForegroundColor Gray
    Write-Host "  [4] Uninstall" -ForegroundColor Gray
    Write-Host "  [5] Cancel" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "Enter choice [1-5]"
    
    switch ($choice) {
        "1" {
            # Update - download latest from GitHub
            Write-Host "`nChecking for updates..." -ForegroundColor Cyan
            
            try {
                $updateUrl = "https://api.github.com/repos/Bananz0/eGPUae/releases/latest"
                $releaseInfo = Invoke-RestMethod -Uri $updateUrl -ErrorAction Stop
                $latestVersion = $releaseInfo.tag_name.TrimStart("v")
                
                Write-Host "Latest version: $latestVersion" -ForegroundColor Green
                
                if ($latestVersion -eq $currentVersion) {
                    Write-Host "`n✓ You already have the latest version installed!" -ForegroundColor Green
                    pause
                    exit
                }
                
                Write-Host "`nDownloading latest version..." -ForegroundColor Yellow
                
                # Download eGPU.ps1
                $eGPUUrl = "https://raw.githubusercontent.com/Bananz0/eGPUae/main/eGPU.ps1"
                $installerUrl = "https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1"
                
                $tempPath = Join-Path $env:TEMP "egpu-update"
                if (-not (Test-Path $tempPath)) {
                    New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
                }
                
                $tempEGPU = Join-Path $tempPath "eGPU.ps1"
                $tempInstaller = Join-Path $tempPath "Install-eGPU-Startup.ps1"
                
                Write-Host "  Downloading eGPU.ps1..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $eGPUUrl -OutFile $tempEGPU -ErrorAction Stop
                
                Write-Host "  Downloading Install-eGPU-Startup.ps1..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $installerUrl -OutFile $tempInstaller -ErrorAction Stop
                
                # Stop running monitor (safely)
                Write-Host "  Checking for running monitor..." -ForegroundColor Gray
                $runningProcesses = Get-Process | Where-Object { $_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*" }
                if ($runningProcesses) {
                    Write-Host "  Stopping eGPU monitor gracefully..." -ForegroundColor Yellow
                    $runningProcesses | ForEach-Object {
                        try {
                            $_.CloseMainWindow() | Out-Null
                            Start-Sleep -Milliseconds 500
                            if (-not $_.HasExited) {
                                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                            }
                        }
                        catch {
                            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Sleep -Seconds 2
                    Write-Host "  ✓ Monitor stopped" -ForegroundColor Green
                }
                else {
                    Write-Host "  ✓ No running monitor detected" -ForegroundColor Green
                }
                
                # Load and preserve current config
                $existingConfig = $null
                if (Test-Path $configPath) {
                    $existingConfig = Get-Content $configPath | ConvertFrom-Json
                    Write-Host "`n✓ Existing settings preserved:" -ForegroundColor Green
                    Write-Host "  • eGPU: $($existingConfig.eGPU_Name)" -ForegroundColor Gray
                }
                
                # Copy new files
                Write-Host "`n  Installing updated files..." -ForegroundColor Gray
                Copy-Item $tempEGPU -Destination $monitorScriptPath -Force
                
                # Check for new features not in existing config
                $newFeaturesAvailable = @()
                if ($existingConfig) {
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'PreventPCSleep') {
                        $newFeaturesAvailable += "PC Sleep Prevention"
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'eGPUDisplayTimeoutMinutes') {
                        $newFeaturesAvailable += "Display Timeout (OLED protection)"
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'TrackStatistics') {
                        $newFeaturesAvailable += "Connection Statistics"
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'AutoLaunchApps') {
                        $newFeaturesAvailable += "Auto-Launch Apps"
                    }
                }
                
                # Offer to configure new features
                if ($newFeaturesAvailable.Count -gt 0) {
                    Write-Host "`n========================================" -ForegroundColor Cyan
                    Write-Host "  New Features Available!" -ForegroundColor Cyan
                    Write-Host "========================================" -ForegroundColor Cyan
                    Write-Host ""
                    foreach ($feature in $newFeaturesAvailable) {
                        Write-Host "  • $feature" -ForegroundColor Yellow
                    }
                    Write-Host ""
                    Write-Host "Would you like to configure these new features now?" -ForegroundColor White
                    Write-Host "  [1] Yes - Configure new features" -ForegroundColor Gray
                    Write-Host "  [2] No - Keep defaults and finish update" -ForegroundColor Gray
                    Write-Host ""
                    
                    $configChoice = Read-Host "Your choice [1-2]"
                    
                    if ($configChoice -eq "1") {
                        # Set defaults for new features, then let user configure
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'PreventPCSleep') {
                            $existingConfig | Add-Member -NotePropertyName 'PreventPCSleep' -NotePropertyValue $false -Force
                            $existingConfig | Add-Member -NotePropertyName 'PCSleepTimeoutMinutes' -NotePropertyValue $null -Force
                        }
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'eGPUDisplayTimeoutMinutes') {
                            $existingConfig | Add-Member -NotePropertyName 'eGPUDisplayTimeoutMinutes' -NotePropertyValue 10 -Force
                        }
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'EnableNotifications') {
                            $existingConfig | Add-Member -NotePropertyName 'EnableNotifications' -NotePropertyValue $true -Force
                        }
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'TrackStatistics') {
                            $existingConfig | Add-Member -NotePropertyName 'TrackStatistics' -NotePropertyValue $true -Force
                        }
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'AutoLaunchApps') {
                            $existingConfig | Add-Member -NotePropertyName 'AutoLaunchApps' -NotePropertyValue @() -Force
                            $existingConfig | Add-Member -NotePropertyName 'CloseLaunchersOnDisconnect' -NotePropertyValue $false -Force
                        }
                        if (-not $existingConfig.PSObject.Properties.Name -contains 'Statistics') {
                            $existingConfig | Add-Member -NotePropertyName 'Statistics' -NotePropertyValue @{
                                TotalConnectCount         = 0
                                TotalConnectedTimeMinutes = 0
                                LastConnected             = $null
                                LastDisconnected          = $null
                            } -Force
                        }
                        
                        # Save config with defaults
                        $existingConfig.InstalledVersion = $latestVersion
                        $existingConfig | ConvertTo-Json -Depth 3 | Set-Content $configPath
                        
                        # Cleanup temp files
                        Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
                        
                        Write-Host "`n✓ Update downloaded. Launching configuration..." -ForegroundColor Green
                        Write-Host "  (Select option 2 - Reconfigure when prompted)`n" -ForegroundColor Gray
                        Start-Sleep -Seconds 2
                        
                        # Re-run installer in reconfigure mode
                        & $tempInstaller
                        exit
                    }
                }
                
                # Just update with defaults for new features
                if ($existingConfig) {
                    # Add defaults for any missing new features
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'PreventPCSleep') {
                        $existingConfig | Add-Member -NotePropertyName 'PreventPCSleep' -NotePropertyValue $false -Force
                        $existingConfig | Add-Member -NotePropertyName 'PCSleepTimeoutMinutes' -NotePropertyValue $null -Force
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'eGPUDisplayTimeoutMinutes') {
                        $existingConfig | Add-Member -NotePropertyName 'eGPUDisplayTimeoutMinutes' -NotePropertyValue 10 -Force
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'EnableNotifications') {
                        $existingConfig | Add-Member -NotePropertyName 'EnableNotifications' -NotePropertyValue $true -Force
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'TrackStatistics') {
                        $existingConfig | Add-Member -NotePropertyName 'TrackStatistics' -NotePropertyValue $true -Force
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'AutoLaunchApps') {
                        $existingConfig | Add-Member -NotePropertyName 'AutoLaunchApps' -NotePropertyValue @() -Force
                        $existingConfig | Add-Member -NotePropertyName 'CloseLaunchersOnDisconnect' -NotePropertyValue $false -Force
                    }
                    if (-not $existingConfig.PSObject.Properties.Name -contains 'Statistics') {
                        $existingConfig | Add-Member -NotePropertyName 'Statistics' -NotePropertyValue @{
                            TotalConnectCount         = 0
                            TotalConnectedTimeMinutes = 0
                            LastConnected             = $null
                            LastDisconnected          = $null
                        } -Force
                    }
                    
                    $existingConfig.InstalledVersion = $latestVersion
                    $existingConfig | ConvertTo-Json -Depth 3 | Set-Content $configPath
                }
                
                # Restart the scheduled task
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($task) {
                    Write-Host "  Restarting monitor..." -ForegroundColor Gray
                    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                }
                
                # Cleanup
                Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue
                
                Write-Host "`n✓ Successfully updated to version $latestVersion!" -ForegroundColor Green
                Write-Host "Your existing settings have been preserved." -ForegroundColor Gray
                if ($newFeaturesAvailable.Count -gt 0) {
                    Write-Host "New features added with sensible defaults. Run installer again to configure." -ForegroundColor Gray
                }
                Write-Host "The eGPU monitor is now running with the latest version." -ForegroundColor Gray
                
            }
            catch {
                Write-Host "`n✗ Update failed: $_" -ForegroundColor Red
                Write-Host "You can manually download from: https://github.com/Bananz0/eGPUae" -ForegroundColor Yellow
            }
            
            pause
            exit
        }
        "2" {
            # Reconfigure - keep this simple, just continue with install
            Write-Host "`nReconfiguring..." -ForegroundColor Yellow
            Write-Host "Keeping your installation folder and proceeding to configuration.`n" -ForegroundColor Gray
            # Continue to main install flow
        }
        "3" {
            # Reinstall
            Write-Host "`n========================================" -ForegroundColor Yellow
            Write-Host "  REINSTALLING" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            
            # Stop processes
            Write-Host "`n[1/3] Stopping running monitor..." -ForegroundColor Gray
            $runningProcesses = Get-Process | Where-Object { $_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*" }
            if ($runningProcesses) {
                $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Write-Host "  ✓ Stopped" -ForegroundColor Green
            }
            else {
                Write-Host "  • No running monitor" -ForegroundColor DarkGray
            }
            
            # Remove task
            Write-Host "[2/3] Removing scheduled task..." -ForegroundColor Gray
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "  ✓ Removed" -ForegroundColor Green
            }
            else {
                Write-Host "  • No task found" -ForegroundColor DarkGray
            }
            
            # Remove folder
            Write-Host "[3/3] Removing old installation..." -ForegroundColor Gray
            if (Test-Path $installPath) {
                Remove-Item $installPath -Recurse -Force
                Write-Host "  ✓ Removed" -ForegroundColor Green
            }
            else {
                Write-Host "  • No folder found" -ForegroundColor DarkGray
            }
            
            Write-Host "`nStarting fresh installation...`n" -ForegroundColor Green
            Start-Sleep -Seconds 1
            # Continue to main install flow
        }
        "4" {
            # Run uninstall inline
            Write-Host "`nUninstalling..." -ForegroundColor Yellow
            
            # Stop running processes
            $runningProcesses = Get-Process | Where-Object { $_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*" }
            if ($runningProcesses) {
                Write-Host "  Stopping running eGPU monitor processes..." -ForegroundColor Gray
                $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            
            # Remove scheduled task
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Write-Host "  Removing scheduled task..." -ForegroundColor Gray
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "  ✓ Task removed" -ForegroundColor Green
            }
            else {
                Write-Host "  • Task not found (already removed)" -ForegroundColor DarkGray
            }
            
            # Remove installation folder
            if (Test-Path $installPath) {
                Write-Host "  Removing installation folder..." -ForegroundColor Gray
                try {
                    Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
                    Write-Host "  ✓ Folder removed" -ForegroundColor Green
                }
                catch {
                    Write-Host "  ⚠ Could not remove folder automatically" -ForegroundColor Yellow
                    Write-Host "  Please manually delete: $installPath" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  • Folder not found (already removed)" -ForegroundColor DarkGray
            }
            
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "  Uninstall Complete!" -ForegroundColor Green
            Write-Host "========================================`n" -ForegroundColor Green
            
            Write-Host "eGPU Auto-Enable has been removed from your system." -ForegroundColor White
            Write-Host "You will need to manually enable your eGPU from Device Manager after reconnecting.`n" -ForegroundColor Gray
            
            pause
            exit
        }
        default {
            Write-Host "`nCancelled." -ForegroundColor Yellow
            pause
            exit
        }
    }
}

# ==================== STEP 1: GPU SELECTION ====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 1: Select Your eGPU" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Scanning for graphics devices...`n" -ForegroundColor Yellow

$allGPUs = Get-PnpDevice -Class Display | Where-Object { 
    $_.FriendlyName -notlike "*Basic Display Adapter*" -and 
    $_.FriendlyName -notlike "*Microsoft*" 
} | Sort-Object FriendlyName

if ($allGPUs.Count -eq 0) {
    Write-Host "ERROR: No graphics devices found!" -ForegroundColor Red
    pause
    exit
}

Write-Host "Found $($allGPUs.Count) graphics device(s):`n" -ForegroundColor Green

# Display all GPUs with index
for ($i = 0; $i -lt $allGPUs.Count; $i++) {
    $gpu = $allGPUs[$i]
    $statusColor = if ($gpu.Status -eq "OK") { "Green" } else { "Yellow" }
    $statusSymbol = if ($gpu.Status -eq "OK") { "✓" } else { "⚠" }
    
    Write-Host "  [$($i + 1)] " -NoNewline -ForegroundColor Cyan
    Write-Host "$statusSymbol $($gpu.FriendlyName)" -ForegroundColor $statusColor
    Write-Host "      Status: $($gpu.Status)" -ForegroundColor Gray
    Write-Host "      Instance ID: $($gpu.InstanceId)" -ForegroundColor DarkGray
    Write-Host ""
}

# Step 2: Let user select their eGPU
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Which device is your eGPU?" -ForegroundColor Yellow
Write-Host "(The one you connect via Thunderbolt/USB-C that you want to auto-enable)" -ForegroundColor Gray
Write-Host ""

do {
    $selection = Read-Host "Enter the number [1-$($allGPUs.Count)]"
    $selectedIndex = [int]$selection - 1
    
    if ($selectedIndex -lt 0 -or $selectedIndex -ge $allGPUs.Count) {
        Write-Host "Invalid selection. Please enter a number between 1 and $($allGPUs.Count)." -ForegroundColor Red
    }
} while ($selectedIndex -lt 0 -or $selectedIndex -ge $allGPUs.Count)

$selectedGPU = $allGPUs[$selectedIndex]

Write-Host "`nYou selected:" -ForegroundColor Green
Write-Host "  $($selectedGPU.FriendlyName)" -ForegroundColor Cyan
Write-Host "  Instance ID: $($selectedGPU.InstanceId)" -ForegroundColor Gray

$confirm = Read-Host "`nIs this correct? (Y/N)"
if ($confirm -notlike "y*") {
    Write-Host "Installation cancelled." -ForegroundColor Yellow
    pause
    exit
}

# ==================== STEP 2: POWER & FEATURE SETTINGS ====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: Power & Feature Settings" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Configure how your system behaves when the eGPU is connected.`n" -ForegroundColor Gray

# --- 2a: PC Sleep Prevention ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "PC Sleep Prevention:" -ForegroundColor Yellow
Write-Host "Keep PC awake when eGPU is connected? (for renders, downloads, etc.)" -ForegroundColor Gray
Write-Host ""
Write-Host "  [1] Yes - Keep awake for 1 hour, then allow sleep" -ForegroundColor Gray
Write-Host "  [2] Yes - Keep awake for 2 hours" -ForegroundColor Gray
Write-Host "  [3] Yes - Keep awake for 4 hours" -ForegroundColor Gray
Write-Host "  [4] Yes - Never sleep while eGPU connected" -ForegroundColor Gray
Write-Host "  [5] No - Use normal sleep settings" -ForegroundColor Gray
Write-Host ""

$pcSleepChoice = Read-Host "Your choice [1-5]"
$preventPCSleep = $false
$pcSleepTimeoutMinutes = $null

switch ($pcSleepChoice) {
    "1" { $preventPCSleep = $true; $pcSleepTimeoutMinutes = 60; Write-Host "✓ PC will stay awake for 1 hour" -ForegroundColor Green }
    "2" { $preventPCSleep = $true; $pcSleepTimeoutMinutes = 120; Write-Host "✓ PC will stay awake for 2 hours" -ForegroundColor Green }
    "3" { $preventPCSleep = $true; $pcSleepTimeoutMinutes = 240; Write-Host "✓ PC will stay awake for 4 hours" -ForegroundColor Green }
    "4" { $preventPCSleep = $true; $pcSleepTimeoutMinutes = 0; Write-Host "✓ PC will never sleep while eGPU connected" -ForegroundColor Green }
    default { $preventPCSleep = $false; Write-Host "✓ Normal sleep settings will apply" -ForegroundColor Green }
}

Write-Host ""

# --- 2b: Display Timeout (OLED Protection) ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Display Timeout (OLED burn-in protection):" -ForegroundColor Yellow
Write-Host "When eGPU is connected, when should the display turn off?" -ForegroundColor Gray
Write-Host ""
Write-Host "  [1] 5 minutes (recommended for OLED)" -ForegroundColor Green
Write-Host "  [2] 10 minutes" -ForegroundColor Gray
Write-Host "  [3] 15 minutes" -ForegroundColor Gray
Write-Host "  [4] 30 minutes" -ForegroundColor Gray
Write-Host "  [5] Never (only for non-OLED displays)" -ForegroundColor Yellow
Write-Host "  [6] Use current Windows setting" -ForegroundColor DarkGray
Write-Host ""

$displayChoice = Read-Host "Your choice [1-6]"
$eGPUDisplayTimeoutMinutes = $null

switch ($displayChoice) {
    "1" { $eGPUDisplayTimeoutMinutes = 5; Write-Host "✓ Display will turn off after 5 minutes" -ForegroundColor Green }
    "2" { $eGPUDisplayTimeoutMinutes = 10; Write-Host "✓ Display will turn off after 10 minutes" -ForegroundColor Green }
    "3" { $eGPUDisplayTimeoutMinutes = 15; Write-Host "✓ Display will turn off after 15 minutes" -ForegroundColor Green }
    "4" { $eGPUDisplayTimeoutMinutes = 30; Write-Host "✓ Display will turn off after 30 minutes" -ForegroundColor Green }
    "5" { $eGPUDisplayTimeoutMinutes = 0; Write-Host "⚠ Display will never turn off (not recommended for OLED)" -ForegroundColor Yellow }
    default { $eGPUDisplayTimeoutMinutes = $null; Write-Host "✓ Will use current Windows display setting" -ForegroundColor Green }
}

Write-Host ""

# --- 2c: Display Timeout when Disconnected ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Display Timeout (when eGPU disconnected):" -ForegroundColor Yellow

# Get current display timeout setting
$currentDisplayTimeout = "Unknown"
try {
    $rawLine = powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE |
    Select-String "Current AC Power Setting Index" -SimpleMatch |
    ForEach-Object { $_.Line.Trim() } | Select-Object -First 1
    
    if ($rawLine -match "0x[0-9A-Fa-f]+") {
        $hex = $Matches[0]
        $seconds = [Convert]::ToInt32($hex, 16)
        if ($seconds -eq 0) {
            $currentDisplayTimeout = "Never"
        }
        else {
            $minutes = [math]::Ceiling($seconds / 60)
            $currentDisplayTimeout = "$minutes minutes"
        }
    }
}
catch {
    $currentDisplayTimeout = "Unable to detect"
}

# Get current lid close action
$currentLidAction = "Unknown"
$currentLidActionValue = $null
try {
    $powerNamespace = @{ Namespace = 'root\cimv2\power' }
    $curPlan = Get-CimInstance @powerNamespace -Class Win32_PowerPlan -Filter "IsActive = TRUE"
    $lidSetting = Get-CimInstance @powerNamespace -ClassName Win32_Powersetting -Filter "ElementName = 'Lid close action'"
    
    if ($curPlan -and $lidSetting) {
        $planGuid = [Regex]::Matches($curPlan.InstanceId, "{.*}").Value
        $lidGuid = [Regex]::Matches($lidSetting.InstanceID, "{.*}").Value
        
        $pluggedInLidSetting = Get-CimInstance @powerNamespace -ClassName Win32_PowerSettingDataIndex `
            -Filter "InstanceID = 'Microsoft:PowerSettingDataIndex\\$planGuid\\AC\\$lidGuid'"
        
        if ($pluggedInLidSetting) {
            $currentLidActionValue = $pluggedInLidSetting.SettingIndexValue
            $currentLidAction = switch ($currentLidActionValue) {
                0 { "Do Nothing" }
                1 { "Sleep" }
                2 { "Hibernate" }
                3 { "Shut Down" }
                default { "Unknown" }
            }
        }
    }
}
catch {
    $currentLidAction = "Unable to detect"
}

# Display sleep timeout preference
Write-Host "Current setting: $currentDisplayTimeout (AC Power)" -ForegroundColor Cyan
Write-Host "(Enter minutes, 0 for 'Never', or press Enter to keep current)" -ForegroundColor DarkGray
$displayTimeout = Read-Host "Minutes"

$displayTimeoutValue = $null
if (-not [string]::IsNullOrWhiteSpace($displayTimeout)) {
    try {
        $displayTimeoutValue = [int]$displayTimeout
        if ($displayTimeoutValue -lt 0) {
            Write-Host "Invalid value. Will use system default." -ForegroundColor Yellow
            $displayTimeoutValue = $null
        }
        else {
            Write-Host "✓ Will restore to $displayTimeoutValue minutes when eGPU disconnected" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Invalid input. Will use system default." -ForegroundColor Yellow
        $displayTimeoutValue = $null
    }
}

if ($null -eq $displayTimeoutValue) {
    Write-Host "✓ Will use system's current setting when restoring" -ForegroundColor Green
}

Write-Host ""

# Lid close action preferences
Write-Host "Lid Close Action (AC Power):" -ForegroundColor Yellow
Write-Host "Current setting: $currentLidAction" -ForegroundColor Cyan
Write-Host ""
Write-Host "What should happen when you close the lid while plugged in?" -ForegroundColor Gray
Write-Host ""
Write-Host "When eGPU is CONNECTED:" -ForegroundColor Cyan
Write-Host "  The script will automatically set lid action to 'Do Nothing'" -ForegroundColor Gray
Write-Host "  (Prevents sleep so external monitors keep working)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "When eGPU is DISCONNECTED, restore lid action to:" -ForegroundColor Cyan
Write-Host "  [0] Do Nothing" -ForegroundColor Gray
Write-Host "  [1] Sleep (most common)" -ForegroundColor Gray
Write-Host "  [2] Hibernate" -ForegroundColor Gray
Write-Host "  [3] Shut Down" -ForegroundColor Gray
Write-Host "  [Enter] Keep current system setting ($currentLidAction)" -ForegroundColor DarkGray

$lidActionInput = Read-Host "`nYour choice"
$lidActionValue = $null

if (-not [string]::IsNullOrWhiteSpace($lidActionInput)) {
    try {
        $lidActionValue = [int]$lidActionInput
        if ($lidActionValue -lt 0 -or $lidActionValue -gt 3) {
            Write-Host "Invalid value. Will use system default." -ForegroundColor Yellow
            $lidActionValue = $null
        }
        else {
            $lidActionName = switch ($lidActionValue) { 0 { "Do Nothing" } 1 { "Sleep" } 2 { "Hibernate" } 3 { "Shut Down" } }
            Write-Host "✓ Will restore to '$lidActionName' when eGPU disconnected" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Invalid input. Will use system default." -ForegroundColor Yellow
        $lidActionValue = $null
    }
}

if ($null -eq $lidActionValue) {
    Write-Host "✓ Will use system's current setting when restoring" -ForegroundColor Green
    # Use the detected current value as the preference
    if ($null -ne $currentLidActionValue) {
        $lidActionValue = $currentLidActionValue
    }
}


# --- 2e: Notifications ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Notifications:" -ForegroundColor Yellow
Write-Host "Show Windows notifications for eGPU connect/disconnect events?" -ForegroundColor Gray
Write-Host "  ⚠ Note: Currently WIP - may not work when running as system service" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "  [1] Yes (recommended)" -ForegroundColor Gray
Write-Host "  [2] No" -ForegroundColor Gray
Write-Host ""

$notifyChoice = Read-Host "Your choice [1-2]"
$enableNotifications = $notifyChoice -ne "2"
if ($enableNotifications) {
    Write-Host "✓ Notifications enabled" -ForegroundColor Green
}
else {
    Write-Host "✓ Notifications disabled" -ForegroundColor Green
}

Write-Host ""

# --- 2f: Connection Statistics ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Connection Statistics:" -ForegroundColor Yellow
Write-Host "Track eGPU connection count, total connected time, etc.?" -ForegroundColor Gray
Write-Host "  📊 Local only - no data is EVER sent anywhere" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  [1] Yes" -ForegroundColor Gray
Write-Host "  [2] No" -ForegroundColor Gray
Write-Host ""

$statsChoice = Read-Host "Your choice [1-2]"
$trackStatistics = $statsChoice -ne "2"
if ($trackStatistics) {
    Write-Host "✓ Statistics tracking enabled (local only)" -ForegroundColor Green
}
else {
    Write-Host "✓ Statistics tracking disabled" -ForegroundColor Green
}

Write-Host ""

# --- 2g: Auto-Launch Apps ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Auto-Launch Apps:" -ForegroundColor Yellow
Write-Host "Launch game launchers automatically when eGPU connects?" -ForegroundColor Gray
Write-Host ""

# Detect installed launchers
$launchers = @{
    "Steam"           = "${env:ProgramFiles(x86)}\Steam\steam.exe"
    "Epic Games"      = "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
    "GOG Galaxy"      = "${env:ProgramFiles(x86)}\GOG Galaxy\GalaxyClient.exe"
    "Playnite"        = "${env:LOCALAPPDATA}\Playnite\Playnite.DesktopApp.exe"
    "Ubisoft Connect" = "${env:ProgramFiles(x86)}\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe"
    "EA App"          = "${env:ProgramFiles}\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
    "Battle.net"      = "${env:ProgramFiles(x86)}\Battle.net\Battle.net Launcher.exe"
}

$installedLaunchers = @{}
$launcherIndex = 1
foreach ($launcher in $launchers.GetEnumerator()) {
    if (Test-Path $launcher.Value) {
        $installedLaunchers[$launcherIndex] = @{ Name = $launcher.Key; Path = $launcher.Value }
        Write-Host "  [$launcherIndex] $($launcher.Key)" -ForegroundColor Gray
        $launcherIndex++
    }
}

$autoLaunchApps = @()
$closeLaunchersOnDisconnect = $false

if ($installedLaunchers.Count -gt 0) {
    Write-Host "  [0] None" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Enter numbers separated by comma (e.g., 1,2,3) or 0 for none:" -ForegroundColor DarkGray
    $launchChoice = Read-Host "Your choice"
    
    if ($launchChoice -ne "0" -and -not [string]::IsNullOrWhiteSpace($launchChoice)) {
        $choices = $launchChoice -split "," | ForEach-Object { $_.Trim() }
        foreach ($choice in $choices) {
            try {
                $idx = [int]$choice
                if ($installedLaunchers.ContainsKey($idx)) {
                    $autoLaunchApps += $installedLaunchers[$idx]
                    Write-Host "  ✓ Will launch $($installedLaunchers[$idx].Name)" -ForegroundColor Green
                }
            }
            catch { }
        }
        
        if ($autoLaunchApps.Count -gt 0) {
            Write-Host ""
            Write-Host "Close these apps when eGPU disconnects?" -ForegroundColor Gray
            Write-Host "  [1] Yes   [2] No" -ForegroundColor Gray
            $closeChoice = Read-Host "Your choice"
            $closeLaunchersOnDisconnect = $closeChoice -eq "1"
            if ($closeLaunchersOnDisconnect) {
                Write-Host "✓ Apps will be closed on disconnect" -ForegroundColor Green
            }
        }
    }
}
else {
    Write-Host "  No common game launchers detected" -ForegroundColor DarkGray
}

if ($autoLaunchApps.Count -eq 0) {
    Write-Host "✓ No apps will be auto-launched" -ForegroundColor Green
}

Write-Host ""

# --- 2h: Safe-Eject Hotkey ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Safe-Eject Hotkey:" -ForegroundColor Yellow
Write-Host "Enable a global hotkey (Ctrl+Alt+E) to safely eject the eGPU?" -ForegroundColor Gray
Write-Host "  This will use your GPU vendor's official eject method if available" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [1] Yes - Enable hotkey" -ForegroundColor Gray
Write-Host "  [2] No" -ForegroundColor Gray
Write-Host ""

$hotkeyChoice = Read-Host "Your choice [1-2]"
$enableSafeEjectHotkey = $hotkeyChoice -eq "1"
if ($enableSafeEjectHotkey) {
    Write-Host "✓ Safe-eject hotkey enabled (Ctrl+Alt+E)" -ForegroundColor Green
}
else {
    Write-Host "✓ Safe-eject hotkey disabled" -ForegroundColor Green
}

Write-Host ""

# --- 2i: Pre-Disconnect Warning ---
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "Pre-Disconnect Warning:" -ForegroundColor Yellow
Write-Host "Warn before safe-ejecting if GPU-intensive apps are running?" -ForegroundColor Gray
Write-Host "  (Detects games, video editors, 3D apps, etc.)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [1] Yes (recommended)" -ForegroundColor Gray
Write-Host "  [2] No" -ForegroundColor Gray
Write-Host ""

$warnChoice = Read-Host "Your choice [1-2]"
$preDisconnectWarning = $warnChoice -ne "2"
if ($preDisconnectWarning) {
    Write-Host "✓ Pre-disconnect warning enabled" -ForegroundColor Green
}
else {
    Write-Host "✓ Pre-disconnect warning disabled" -ForegroundColor Green
}

Write-Host ""
# ==================== STEP 3: POWER PLAN CREATION ====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 3: eGPU Performance Power Plan" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "eGPU High Performance Power Plan:" -ForegroundColor Yellow
Write-Host "Create a custom power plan optimized for maximum eGPU performance?" -ForegroundColor Gray
Write-Host "  - Based on High Performance plan" -ForegroundColor Gray
Write-Host "  - CPU: Maximum performance (100% min/max)" -ForegroundColor Gray
Write-Host "  - PCIe Link State: Maximum performance" -ForegroundColor Gray
Write-Host "  - USB: No selective suspend" -ForegroundColor Gray
Write-Host "  - Automatically switches when eGPU connects/disconnects" -ForegroundColor Gray
$createPowerPlan = Read-Host "`nCreate eGPU power plan? (Y/N)"

$eGPUPowerPlanGuid = $null
$originalPowerPlanGuid = $null

if ($createPowerPlan -like "y*") {
    Write-Host "`nCreating eGPU High Performance power plan..." -ForegroundColor Yellow
    
    try {
        # Save the current active power plan before creating eGPU plan
        $currentPlan = powercfg -GETACTIVESCHEME
        if ($currentPlan -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
            $originalPowerPlanGuid = $Matches[1]
            Write-Host "  Current power plan saved: $originalPowerPlanGuid" -ForegroundColor DarkGray
        }
        
        # Check if plan already exists and delete it to create fresh
        $existingPlan = powercfg -list | Select-String "eGPU High Performance"
        if ($existingPlan) {
            # Extract GUID from existing plan
            if ($existingPlan -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
                $oldPlanGuid = $Matches[1]
                Write-Host "  Found existing eGPU power plan, deleting to create fresh..." -ForegroundColor Yellow
                powercfg -delete $oldPlanGuid 2>&1 | Out-Null
            }
        }
        
        # Create new plan based on High Performance
        $result = powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
        if ($result -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
            $eGPUPowerPlanGuid = $Matches[1]
            
            # Rename the power plan
            powercfg -changename $eGPUPowerPlanGuid "eGPU High Performance" "Optimized for maximum eGPU performance" 2>&1 | Out-Null
            
            # Configure for maximum performance (some settings may not be available on all systems)
            # CPU: 100% minimum and maximum
            powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>&1 | Out-Null
            powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>&1 | Out-Null
            
            # PCIe Link State Power Management: Off (maximum performance)
            powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PCIEXPRESS ASPM 0 2>&1 | Out-Null
            
            # USB selective suspend: Disabled
            powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_USB USBSELECTIVESUSPEND 0 2>&1 | Out-Null
            
            # Hard disk: Never turn off
            powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_DISK DISKIDLE 0 2>&1 | Out-Null
            
            # Display timeout: Use user's configured eGPU display timeout (OLED protection)
            if ($null -ne $eGPUDisplayTimeoutMinutes) {
                $displaySeconds = $eGPUDisplayTimeoutMinutes * 60
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_VIDEO VIDEOIDLE $displaySeconds 2>&1 | Out-Null
            }
            else {
                # Default to 10 minutes if not set (safe for OLED)
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_VIDEO VIDEOIDLE 600 2>&1 | Out-Null
            }
            
            # PC Sleep: Use user's configured PC sleep timeout
            if ($preventPCSleep) {
                if ($null -ne $pcSleepTimeoutMinutes -and $pcSleepTimeoutMinutes -gt 0) {
                    $sleepSeconds = $pcSleepTimeoutMinutes * 60
                    powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_SLEEP STANDBYIDLE $sleepSeconds 2>&1 | Out-Null
                }
                else {
                    # Never sleep
                    powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_SLEEP STANDBYIDLE 0 2>&1 | Out-Null
                }
            }
            
            # Only activate if eGPU is currently connected and working
            $isEGPUConnected = $selectedGPU.Status -eq "OK"
            if ($isEGPUConnected) {
                powercfg -setactive $eGPUPowerPlanGuid | Out-Null
                Write-Host "✓ Created and activated eGPU High Performance power plan" -ForegroundColor Green
                Write-Host "  (eGPU is connected)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "✓ Created eGPU High Performance power plan" -ForegroundColor Green
                Write-Host "  (Will activate automatically when eGPU connects)" -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "✗ Failed to create power plan" -ForegroundColor Red
            $eGPUPowerPlanGuid = $null
        }
    }
    catch {
        Write-Host "✗ Failed to create power plan: $_" -ForegroundColor Red
        $eGPUPowerPlanGuid = $null
    }
}
else {
    Write-Host "✓ Skipping power plan creation" -ForegroundColor Green
}

# ==================== STEP 4: INSTALLATION ====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 4: Finalizing Installation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Setting up installation files..." -ForegroundColor Yellow

if (-not (Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
}

# Save configuration
$config = @{
    eGPU_Name                  = $selectedGPU.FriendlyName
    eGPU_InstanceID            = $selectedGPU.InstanceId
    ConfiguredDate             = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    InstalledVersion           = $SCRIPT_VERSION
    AutoUpdateCheck            = $true
    
    # Power settings
    PreventPCSleep             = $preventPCSleep
    PCSleepTimeoutMinutes      = $pcSleepTimeoutMinutes
    eGPUDisplayTimeoutMinutes  = $eGPUDisplayTimeoutMinutes
    
    # Feature toggles
    EnableNotifications        = $enableNotifications
    TrackStatistics            = $trackStatistics
    EnableSafeEjectHotkey      = $enableSafeEjectHotkey
    PreDisconnectWarning       = $preDisconnectWarning
    
    # Auto-launch config
    AutoLaunchApps             = @($autoLaunchApps | ForEach-Object { $_.Path })
    CloseLaunchersOnDisconnect = $closeLaunchersOnDisconnect
    
    # Statistics (initialized)
    Statistics                 = @{
        TotalConnectCount         = 0
        TotalConnectedTimeMinutes = 0
        LastConnected             = $null
        LastDisconnected          = $null
    }
}

# Add display timeout preference if set (for when eGPU disconnected)
if ($null -ne $displayTimeoutValue) {
    $config.DisplayTimeoutMinutes = $displayTimeoutValue
}

# Add lid close action preference if set
if ($null -ne $lidActionValue) {
    $config.LidCloseActionAC = $lidActionValue
}

# Add eGPU power plan GUID if created
if ($null -ne $eGPUPowerPlanGuid) {
    $config.eGPUPowerPlanGuid = $eGPUPowerPlanGuid
}

# Add original power plan GUID to restore to
if ($null -ne $originalPowerPlanGuid) {
    $config.OriginalPowerPlanGuid = $originalPowerPlanGuid
}

$config | ConvertTo-Json -Depth 3 | Set-Content $configPath
Write-Host "✓ Configuration saved" -ForegroundColor Green

# Download or copy the monitor script
$sourceMonitorScriptUrl = "https://raw.githubusercontent.com/Bananz0/eGPUae/main/eGPU.ps1"

# Try to get from local directory first (if installer was run as a file)
$currentScriptDir = if ($MyInvocation.MyCommand.Path) { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
}
else { 
    $null 
}

$sourceMonitorScript = if ($currentScriptDir) { 
    Join-Path $currentScriptDir "eGPU.ps1" 
}
else { 
    $null 
}

if ($sourceMonitorScript -and (Test-Path $sourceMonitorScript)) {
    # Copy from local directory
    Write-Host "✓ Copying monitor script from local directory..." -ForegroundColor Green
    Copy-Item -Path $sourceMonitorScript -Destination $monitorScriptPath -Force
}
else {
    # Download from GitHub
    Write-Host "✓ Downloading monitor script from GitHub..." -ForegroundColor Green
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($sourceMonitorScriptUrl, $monitorScriptPath)
        Write-Host "✓ Downloaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠ Failed to download eGPU.ps1 from GitHub" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host "`nPlease manually download eGPU.ps1 from:" -ForegroundColor Yellow
        Write-Host "  https://github.com/Bananz0/eGPUae/blob/main/eGPU.ps1" -ForegroundColor Yellow
        Write-Host "And place it in: $installPath" -ForegroundColor Yellow
        pause
        exit
    }
}

Write-Host "✓ Monitor script installed" -ForegroundColor Green

# Step 4: Create scheduled task
Write-Host "✓ Creating startup task..." -ForegroundColor Green

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$taskDescription = "Automatically enables $($selectedGPU.FriendlyName) after physical reconnection"

# Create the action
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitorScriptPath`""

# Create the trigger (at startup, with 10 second delay)
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT10S"

# Create principal - Use S4U for better reliability when running manually
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Hours 0) -MultipleInstances IgnoreNew

# Register the task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "✓ Scheduled task created" -ForegroundColor Green

# Step 5: Show completion info and offer to start now
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  eGPU: $($selectedGPU.FriendlyName)" -ForegroundColor White
Write-Host "  Instance ID: $($selectedGPU.InstanceId)" -ForegroundColor DarkGray
Write-Host "  Location: $installPath" -ForegroundColor Gray
Write-Host "  Task: $taskName" -ForegroundColor Gray
Write-Host "  Log File: $installPath\egpu-manager.log" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Start Monitoring" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nWhen would you like to start the eGPU monitor?" -ForegroundColor Yellow
Write-Host "  [1] Start now (watch live log)" -ForegroundColor Gray
Write-Host "  [2] Start on next reboot (automatic)" -ForegroundColor Gray
Write-Host ""

$startChoice = Read-Host "Your choice [1-2]"

if ($startChoice -eq "1") {
    Write-Host "`nStarting eGPU monitor..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop monitoring`n" -ForegroundColor DarkGray
    Write-Host "========================================`n" -ForegroundColor Gray
    
    Start-Sleep -Seconds 1
    
    # Start the task in background
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    # Wait for log file to be created (up to 5 seconds)
    Write-Host "Waiting for monitor to start..." -ForegroundColor Gray
    $waitCount = 0
    while (-not (Test-Path "$installPath\egpu-manager.log") -and $waitCount -lt 10) {
        Start-Sleep -Milliseconds 500
        $waitCount++
    }
    
    if (Test-Path "$installPath\egpu-manager.log") {
        Write-Host "Monitor started, showing live log:`n" -ForegroundColor Green
        # Tail the log file
        try {
            Get-Content -Path "$installPath\egpu-manager.log" -Wait -Tail 50
        }
        catch {
            Write-Host "`n⚠ Could not tail log file: $_" -ForegroundColor Yellow
            Write-Host "View logs with: Get-Content `"$installPath\egpu-manager.log`" -Tail 50" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "`n⚠ Monitor task started but log file not created yet" -ForegroundColor Yellow
        Write-Host "The monitor may take a moment to initialize." -ForegroundColor Gray
        Write-Host "View logs with: Get-Content `"$installPath\egpu-manager.log`" -Wait" -ForegroundColor Gray
    }
}
else {
    Write-Host "`n✓ Monitor will start automatically on next reboot" -ForegroundColor Green
    Write-Host "  (Starts 10 seconds after Windows boots)" -ForegroundColor DarkGray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Your Workflow" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nUsing your eGPU:" -ForegroundColor Yellow
Write-Host "  1. Safe-remove eGPU in NVIDIA Control Panel" -ForegroundColor Gray
Write-Host "  2. Physically unplug the eGPU" -ForegroundColor Gray
Write-Host "  3. Plug it back in → Automatically enables! ✓" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Quick Commands" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nManually start/stop the monitor:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray
Write-Host "  Stop-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray

Write-Host "`nView logs:" -ForegroundColor Yellow
Write-Host "  Get-Content `"$installPath\egpu-manager.log`" -Tail 50" -ForegroundColor Gray
Write-Host "  Get-Content `"$installPath\egpu-manager.log`" -Wait  # Live tail" -ForegroundColor Gray

Write-Host "`nOpen config folder:" -ForegroundColor Yellow
Write-Host "  explorer `"$installPath`"" -ForegroundColor Gray

Write-Host "`nReconfigure or Update:" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex" -ForegroundColor Gray

Write-Host "`n"
pause