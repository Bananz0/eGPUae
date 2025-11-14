# eGPU Auto-Enable Installer/Uninstaller
# Interactive setup for automatic eGPU re-enabling at startup

# VERSION CONSTANT - Update this when releasing new versions
$SCRIPT_VERSION = "2.1.0"

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
    Version        : 2.1.0
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
    $runningProcesses = Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*"}
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
    } else {
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
            } catch {
                # Silently continue if config can't be read
            }
        }
        
        try {
            Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
            Write-Host "  ✓ Folder removed" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠ Could not remove folder automatically" -ForegroundColor Yellow
            Write-Host "  Please manually delete: $installPath" -ForegroundColor Yellow
        }
    } else {
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
        } catch {}
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
                $runningProcesses = Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*"}
                if ($runningProcesses) {
                    Write-Host "  Stopping eGPU monitor gracefully..." -ForegroundColor Yellow
                    $runningProcesses | ForEach-Object {
                        try {
                            $_.CloseMainWindow() | Out-Null
                            Start-Sleep -Milliseconds 500
                            if (-not $_.HasExited) {
                                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                            }
                        } catch {
                            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Start-Sleep -Seconds 2
                    Write-Host "  ✓ Monitor stopped" -ForegroundColor Green
                } else {
                    Write-Host "  ✓ No running monitor detected" -ForegroundColor Green
                }
                
                # Backup current config
                if (Test-Path $configPath) {
                    $backupConfig = Get-Content $configPath | ConvertFrom-Json
                }
                
                # Copy new files
                Write-Host "  Installing updated files..." -ForegroundColor Gray
                Copy-Item $tempEGPU -Destination $monitorScriptPath -Force
                
                # Update config with new version
                if ($backupConfig) {
                    $backupConfig.InstalledVersion = $latestVersion
                    $backupConfig | ConvertTo-Json | Set-Content $configPath
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
                Write-Host "The eGPU monitor is now running with the latest version." -ForegroundColor Gray
                
            } catch {
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
            $runningProcesses = Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*"}
            if ($runningProcesses) {
                $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Write-Host "  ✓ Stopped" -ForegroundColor Green
            } else {
                Write-Host "  • No running monitor" -ForegroundColor DarkGray
            }
            
            # Remove task
            Write-Host "[2/3] Removing scheduled task..." -ForegroundColor Gray
            $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                Write-Host "  ✓ Removed" -ForegroundColor Green
            } else {
                Write-Host "  • No task found" -ForegroundColor DarkGray
            }
            
            # Remove folder
            Write-Host "[3/3] Removing old installation..." -ForegroundColor Gray
            if (Test-Path $installPath) {
                Remove-Item $installPath -Recurse -Force
                Write-Host "  ✓ Removed" -ForegroundColor Green
            } else {
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
            $runningProcesses = Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -and $_.CommandLine -like "*eGPU.ps1*"}
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
            } else {
                Write-Host "  • Task not found (already removed)" -ForegroundColor DarkGray
            }
            
            # Remove installation folder
            if (Test-Path $installPath) {
                Write-Host "  Removing installation folder..." -ForegroundColor Gray
                try {
                    Remove-Item -Path $installPath -Recurse -Force -ErrorAction Stop
                    Write-Host "  ✓ Folder removed" -ForegroundColor Green
                } catch {
                    Write-Host "  ⚠ Could not remove folder automatically" -ForegroundColor Yellow
                    Write-Host "  Please manually delete: $installPath" -ForegroundColor Yellow
                }
            } else {
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

# ==================== STEP 2: POWER MANAGEMENT ====================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  STEP 2: Power Management Settings" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "The eGPU manager can automatically manage power settings when your eGPU is connected.`n" -ForegroundColor Gray

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
        } else {
            $minutes = [math]::Ceiling($seconds / 60)
            $currentDisplayTimeout = "$minutes minutes"
        }
    }
} catch {
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
                0 {"Do Nothing"}
                1 {"Sleep"}
                2 {"Hibernate"}
                3 {"Shut Down"}
                default {"Unknown"}
            }
        }
    }
} catch {
    $currentLidAction = "Unable to detect"
}

# Display sleep timeout preference
Write-Host "Display Sleep Timeout:" -ForegroundColor Yellow
Write-Host "Current setting: $currentDisplayTimeout (AC Power)" -ForegroundColor Cyan
Write-Host ""
Write-Host "When eGPU disconnected, how many minutes until display sleeps?" -ForegroundColor Gray
Write-Host "(Enter 0 for 'Never', custom minutes, or press Enter to keep current setting)" -ForegroundColor DarkGray
$displayTimeout = Read-Host "Minutes (press Enter to use current system setting)"

$displayTimeoutValue = $null
if (-not [string]::IsNullOrWhiteSpace($displayTimeout)) {
    try {
        $displayTimeoutValue = [int]$displayTimeout
        if ($displayTimeoutValue -lt 0) {
            Write-Host "Invalid value. Will use system default." -ForegroundColor Yellow
            $displayTimeoutValue = $null
        } else {
            Write-Host "✓ Will restore to $displayTimeoutValue minutes when eGPU disconnected" -ForegroundColor Green
        }
    } catch {
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
        } else {
            $lidActionName = switch ($lidActionValue) { 0 {"Do Nothing"} 1 {"Sleep"} 2 {"Hibernate"} 3 {"Shut Down"} }
            Write-Host "✓ Will restore to '$lidActionName' when eGPU disconnected" -ForegroundColor Green
        }
    } catch {
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
if ($createPowerPlan -like "y*") {
    Write-Host "`nCreating eGPU High Performance power plan..." -ForegroundColor Yellow
    
    try {
        # Check if plan already exists
        $existingPlan = powercfg -list | Select-String "eGPU High Performance"
        if ($existingPlan) {
            # Extract GUID from existing plan
            if ($existingPlan -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
                $eGPUPowerPlanGuid = $Matches[1]
                Write-Host "✓ Found existing eGPU power plan" -ForegroundColor Green
            }
        } else {
            # Create new plan based on High Performance
            $result = powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1
            if ($result -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
                $eGPUPowerPlanGuid = $Matches[1]
                
                # Rename the power plan
                powercfg -changename $eGPUPowerPlanGuid "eGPU High Performance" "Optimized for maximum eGPU performance" | Out-Null
                
                # Configure for maximum performance
                # CPU: 100% minimum and maximum
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 | Out-Null
                
                # PCIe Link State Power Management: Off (maximum performance)
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_PCIEXPRESS ASPM 0 | Out-Null
                
                # USB selective suspend: Disabled
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_USB USBSELECTIVESUSPEND 0 | Out-Null
                
                # Hard disk: Never turn off
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_DISK DISKIDLE 0 | Out-Null
                
                # Display: Never turn off (will be managed by script)
                powercfg -setacvalueindex $eGPUPowerPlanGuid SUB_VIDEO VIDEOIDLE 0 | Out-Null
                
                # Only activate if eGPU is currently connected and working
                $isEGPUConnected = $selectedGPU.Status -eq "OK"
                if ($isEGPUConnected) {
                    powercfg -setactive $eGPUPowerPlanGuid | Out-Null
                    Write-Host "✓ Created and activated eGPU High Performance power plan" -ForegroundColor Green
                    Write-Host "  (eGPU is connected)" -ForegroundColor DarkGray
                } else {
                    Write-Host "✓ Created eGPU High Performance power plan" -ForegroundColor Green
                    Write-Host "  (Will activate automatically when eGPU connects)" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "✗ Failed to create power plan" -ForegroundColor Red
                $eGPUPowerPlanGuid = $null
            }
        }
    } catch {
        Write-Host "✗ Failed to create power plan: $_" -ForegroundColor Red
        $eGPUPowerPlanGuid = $null
    }
} else {
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
    eGPU_Name = $selectedGPU.FriendlyName
    eGPU_InstanceID = $selectedGPU.InstanceId
    ConfiguredDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    InstalledVersion = $SCRIPT_VERSION
    AutoUpdateCheck = $true
}

# Add display timeout preference if set
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

$config | ConvertTo-Json | Set-Content $configPath
Write-Host "✓ Configuration saved" -ForegroundColor Green

# Download or copy the monitor script
$sourceMonitorScriptUrl = "https://raw.githubusercontent.com/Bananz0/eGPUae/main/eGPU.ps1"

# Try to get from local directory first (if installer was run as a file)
$currentScriptDir = if ($MyInvocation.MyCommand.Path) { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
} else { 
    $null 
}

$sourceMonitorScript = if ($currentScriptDir) { 
    Join-Path $currentScriptDir "eGPU.ps1" 
} else { 
    $null 
}

if ($sourceMonitorScript -and (Test-Path $sourceMonitorScript)) {
    # Copy from local directory
    Write-Host "✓ Copying monitor script from local directory..." -ForegroundColor Green
    Copy-Item -Path $sourceMonitorScript -Destination $monitorScriptPath -Force
} else {
    # Download from GitHub
    Write-Host "✓ Downloading monitor script from GitHub..." -ForegroundColor Green
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($sourceMonitorScriptUrl, $monitorScriptPath)
        Write-Host "✓ Downloaded successfully" -ForegroundColor Green
    } catch {
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

# Create principal
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Hours 0)

# Register the task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "✓ Scheduled task created" -ForegroundColor Green

# Step 5: Show completion info
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  eGPU: $($selectedGPU.FriendlyName)" -ForegroundColor White
Write-Host "  Location: $installPath" -ForegroundColor Gray
Write-Host "  Task: $taskName" -ForegroundColor Gray
Write-Host "  Startup: Automatic (10 second delay)" -ForegroundColor Gray
Write-Host "  Log File: $installPath\egpu-manager.log" -ForegroundColor Gray
Write-Host "  Log Rotation: Automatic (max 500 KB)" -ForegroundColor Gray

Write-Host "`nYour workflow:" -ForegroundColor Cyan
Write-Host "  1. Safe-remove eGPU in NVIDIA Control Panel" -ForegroundColor Gray
Write-Host "  2. Physically unplug the eGPU" -ForegroundColor Gray
Write-Host "  3. Plug it back in → Automatically enables! ✓" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Quick Commands" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTest now (start monitoring in this window):" -ForegroundColor Yellow
Write-Host "  pwsh `"$monitorScriptPath`"" -ForegroundColor Gray

Write-Host "`nStart the background task now:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray

Write-Host "`nView logs/config folder:" -ForegroundColor Yellow
Write-Host "  explorer `"$installPath`"" -ForegroundColor Gray

Write-Host "`nView latest log entries:" -ForegroundColor Yellow
Write-Host "  Get-Content `"$installPath\egpu-manager.log`" -Tail 50" -ForegroundColor Gray

Write-Host "`nReconfigure (change eGPU):" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex" -ForegroundColor Gray

Write-Host "`nUninstall:" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex" -ForegroundColor Gray
Write-Host "  # Then choose option [3] Uninstall" -ForegroundColor DarkGray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  One-Line Remote Install" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nTo install on another machine, run this as Admin:" -ForegroundColor Yellow
Write-Host "  irm https://raw.githubusercontent.com/Bananz0/eGPUae/main/Install-eGPU-Startup.ps1 | iex" -ForegroundColor Gray

Write-Host "`n"
$testNow = Read-Host "Would you like to test the monitor now in this window? (Y/N)"

if ($testNow -like "y*") {
    Write-Host "`nStarting monitor..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray
    Start-Sleep -Seconds 2
    & pwsh -File $monitorScriptPath
} else {
    Write-Host "`nDone! The monitor will start automatically on next boot." -ForegroundColor Green
    Write-Host "Or start it now with: Start-ScheduledTask -TaskName '$taskName'`n" -ForegroundColor Gray
    pause
}