# eGPU Auto-Start Installer (Interactive)
# This script helps you set up automatic eGPU re-enabling at startup

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    pause
    exit
}

Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  eGPU Auto-Enable Installer" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

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

# Step 3: Save configuration
Write-Host "`nSaving eGPU configuration..." -ForegroundColor Yellow

$config = @{
    eGPU_Name = $selectedGPU.FriendlyName
    eGPU_InstanceID = $selectedGPU.InstanceId
    ConfiguredDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$scriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptFolder "egpu-config.json"
$config | ConvertTo-Json | Set-Content $configPath

Write-Host "✓ Configuration saved to: $configPath" -ForegroundColor Green

# Step 4: Locate the monitoring script
$monitorScriptPath = Join-Path $scriptFolder "eGPU.ps1"

if (-not (Test-Path $monitorScriptPath)) {
    Write-Host "`nERROR: eGPU.ps1 not found in the same folder!" -ForegroundColor Red
    Write-Host "Expected location: $monitorScriptPath" -ForegroundColor Yellow
    Write-Host "`nPlease ensure both scripts are in the same folder:" -ForegroundColor Yellow
    Write-Host "  - Install-eGPU-Startup.ps1 (this script)" -ForegroundColor Gray
    Write-Host "  - eGPU.ps1 (the monitoring script)" -ForegroundColor Gray
    pause
    exit
}

Write-Host "✓ Found monitoring script: $monitorScriptPath" -ForegroundColor Green

# Step 5: Create scheduled task
Write-Host "`nCreating startup task..." -ForegroundColor Yellow

$taskName = "eGPU-AutoEnable"
$taskDescription = "Automatically enables $($selectedGPU.FriendlyName) after physical reconnection"

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task..." -ForegroundColor Gray
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create the action (run PowerShell with the script, hidden window)
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitorScriptPath`""

# Create the trigger (at startup, with 10 second delay to let system stabilize)
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT10S"  # 10 second delay

# Create principal (run with highest privileges)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Hours 0)

# Register the task
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "✓ Scheduled task created successfully!" -ForegroundColor Green

# Step 6: Test the task
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nConfiguration:" -ForegroundColor Cyan
Write-Host "  eGPU: $($selectedGPU.FriendlyName)" -ForegroundColor White
Write-Host "  Script: $monitorScriptPath" -ForegroundColor Gray
Write-Host "  Task: $taskName" -ForegroundColor Gray
Write-Host "  Startup: Automatic (10 second delay)" -ForegroundColor Gray

Write-Host "`nThe eGPU monitor will now start automatically when Windows boots." -ForegroundColor White
Write-Host "`nYour workflow:" -ForegroundColor Cyan
Write-Host "  1. Safe-remove eGPU in NVIDIA Control Panel" -ForegroundColor Gray
Write-Host "  2. Physically unplug the eGPU" -ForegroundColor Gray
Write-Host "  3. Plug it back in → Automatically enables!" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Quick Commands" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nTest now (start monitoring in this window):" -ForegroundColor Yellow
Write-Host "  pwsh `"$monitorScriptPath`"" -ForegroundColor Gray

Write-Host "`nStart the background task now:" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Gray

Write-Host "`nView task in Task Scheduler:" -ForegroundColor Yellow
Write-Host "  taskschd.msc" -ForegroundColor Gray

Write-Host "`nUninstall (remove task):" -ForegroundColor Yellow
Write-Host "  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor Gray

Write-Host "`nReconfigure (run installer again):" -ForegroundColor Yellow
Write-Host "  pwsh `"$($MyInvocation.MyCommand.Path)`"" -ForegroundColor Gray

Write-Host "`n"
$testNow = Read-Host "Would you like to test the monitor now in this window? (Y/N)"

if ($testNow -like "y*") {
    Write-Host "`nStarting monitor..." -ForegroundColor Green
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Gray
    Start-Sleep -Seconds 2
    & pwsh -File $monitorScriptPath
} else {
    Write-Host "`nDone! The monitor will start automatically on next boot." -ForegroundColor Green
    pause
}