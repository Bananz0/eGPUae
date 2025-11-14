# eGPU Auto-Enable Installer/Uninstaller
# Interactive setup for automatic eGPU re-enabling at startup

<#
.SYNOPSIS
    eGPU Auto-Enable Tool - Automatically re-enables eGPU after hot-plugging on Windows

.DESCRIPTION
    This tool monitors your external GPU and automatically enables it whenever you reconnect it after safe-removal.
    It eliminates the need to manually enable the eGPU from Device Manager.

.PARAMETER Uninstall
    (Installer only) Removes the eGPU Auto-Enable tool from your system.

.EXAMPLE
    .\Install-eGPU-Startup.ps1
    Installs the eGPU Auto-Enable tool with interactive configuration.

.EXAMPLE
    .\Install-eGPU-Startup.ps1 -Uninstall
    Removes the eGPU Auto-Enable tool from your system.

.EXAMPLE
    irm https://raw.githubusercontent.com/YourUsername/eGPUae/main/Install-eGPU-Startup.ps1 | iex
    Installs the eGPU Auto-Enable tool in one line.

.NOTES
    File Name      : eGPU.ps1 / Install-eGPU-Startup.ps1
    Prerequisite   : PowerShell 7.0 or later
    Requires Admin : Yes
    Version        : 1.0.0
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

    # In the uninstall section, add these additional cleanup steps
    # Stop any running instances of the script
    $runningProcesses = Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -and $_.MainWindowTitle -like "*eGPU*"}
    if ($runningProcesses) {
        Write-Host "  Stopping running eGPU monitor processes..." -ForegroundColor Gray
        $runningProcesses | Stop-Process -Force
    }

    # Remove registry entries if any
    if (Test-Path "HKCU:\Software\eGPU-AutoEnable") {
        Write-Host "  Removing registry entries..." -ForegroundColor Gray
        Remove-Item -Path "HKCU:\Software\eGPU-AutoEnable" -Recurse -Force
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
    Write-Host "`nWhat would you like to do?" -ForegroundColor Cyan
    Write-Host "  [1] Reconfigure (select different eGPU)" -ForegroundColor Gray
    Write-Host "  [2] Reinstall (fresh installation)" -ForegroundColor Gray
    Write-Host "  [3] Uninstall" -ForegroundColor Gray
    Write-Host "  [4] Cancel" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "Enter choice [1-4]"
    
    switch ($choice) {
        "3" {
            # Restart script in uninstall mode
            & $MyInvocation.MyCommand.Path -Uninstall
            exit
        }
        "4" {
            Write-Host "`nCancelled." -ForegroundColor Yellow
            pause
            exit
        }
        "2" {
            Write-Host "`nUninstalling existing installation..." -ForegroundColor Yellow
            & $MyInvocation.MyCommand.Path -Uninstall
            Write-Host "`nStarting fresh installation..." -ForegroundColor Green
            Start-Sleep -Seconds 2
            Clear-Host
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host "  eGPU Auto-Enable INSTALLER" -ForegroundColor Cyan
            Write-Host "========================================`n" -ForegroundColor Cyan
        }
        "5" {
            Write-Host "`nCreating backup..." -ForegroundColor Green
            $backupPath = Join-Path $env:USERPROFILE "Desktop\egpu-config-backup.json"
            Copy-Item $configPath $backupPath
            Write-Host "Configuration backed up to: $backupPath" -ForegroundColor Green
            pause
        }
        "6" {
            $backupPath = Read-Host "Enter path to backup file"
            if (Test-Path $backupPath) {
                try {
                    $backupConfig = Get-Content $backupPath | ConvertFrom-Json
                    $backupConfig | ConvertTo-Json | Set-Content $configPath
                    Write-Host "Configuration restored successfully!" -ForegroundColor Green
                } catch {
                    Write-Host "Failed to restore configuration: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "Backup file not found!" -ForegroundColor Red
            }
            pause
        }
        default {
            Write-Host "`nReconfiguring..." -ForegroundColor Green
        }
    }
}

# Step 1: Detect all display adapters
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

# Step 3: Create installation directory and save files
Write-Host "`nSetting up installation..." -ForegroundColor Yellow

if (-not (Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
}

# Save configuration
$config = @{
    eGPU_Name = $selectedGPU.FriendlyName
    eGPU_InstanceID = $selectedGPU.InstanceId
    ConfiguredDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    InstalledVersion = "1.0"
}

$config | ConvertTo-Json | Set-Content $configPath
Write-Host "✓ Configuration saved" -ForegroundColor Green

# Download or copy the monitor script
$currentScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceMonitorScript = Join-Path $currentScriptDir "eGPU.ps1"

if (Test-Path $sourceMonitorScript) {
    # Copy from local directory
    Write-Host "✓ Copying monitor script..." -ForegroundColor Green
    Copy-Item -Path $sourceMonitorScript -Destination $monitorScriptPath -Force
} else {
    Write-Host "⚠ eGPU.ps1 not found in current directory" -ForegroundColor Yellow
    Write-Host "Please ensure eGPU.ps1 is in the same folder as the installer, or" -ForegroundColor Yellow
    Write-Host "download it manually to: $installPath" -ForegroundColor Yellow
    pause
    exit
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

Write-Host "`nReconfigure (change eGPU):" -ForegroundColor Yellow
Write-Host "  pwsh -File `"$($MyInvocation.MyCommand.Path)`"" -ForegroundColor Gray

Write-Host "`nUninstall:" -ForegroundColor Yellow
Write-Host "  pwsh -File `"$($MyInvocation.MyCommand.Path)`" -Uninstall" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  One-Line Remote Install" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nTo install on another machine, run this as Admin:" -ForegroundColor Yellow
Write-Host "  irm https://github.com/Bananz0/eGPUae/blob/main/Install-eGPU-Startup.ps1 | iex" -ForegroundColor Gray
Write-Host "`n(Host both eGPU.ps1 and this installer on GitHub/web)" -ForegroundColor DarkGray

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