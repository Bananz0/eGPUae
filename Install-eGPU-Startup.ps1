# eGPU Auto-Start Installer
# Run this script as Administrator to install the eGPU monitor to run at startup

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator', then run this script again."
    pause
    exit
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  eGPU Startup Service Installer" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get the path to the eGPU monitoring script
$scriptPath = Read-Host "Enter the full path to your eGPU.ps1 script (e.g., C:\Users\glenm\OneDrive\Desktop\eGPUae\eGPU.ps1)"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found at: $scriptPath" -ForegroundColor Red
    pause
    exit
}

Write-Host "`nScript found: $scriptPath" -ForegroundColor Green

# Create a scheduled task to run at startup
$taskName = "eGPU-AutoEnable"
$taskDescription = "Automatically enables eGPU after physical reconnection"

# Remove existing task if it exists
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "`nRemoving existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Create the action (run PowerShell with the script, hidden window)
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

# Create the trigger (at startup)
$trigger = New-ScheduledTaskTrigger -AtStartup

# Create principal (run with highest privileges)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

# Create settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

# Register the task
Write-Host "`nCreating scheduled task..." -ForegroundColor Yellow
Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null

Write-Host "✓ Scheduled task created successfully!" -ForegroundColor Green
Write-Host "`nTask Name: $taskName"
Write-Host "Trigger: At system startup"
Write-Host "Script: $scriptPath"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nThe eGPU monitor will now start automatically when Windows boots."
Write-Host "`nTo test it now, you can either:"
Write-Host "  1. Restart your computer"
Write-Host "  2. Manually run: Start-ScheduledTask -TaskName '$taskName'"
Write-Host "`nTo uninstall later, run:"
Write-Host "  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"

Write-Host "`nTo view the task in Task Scheduler:"
Write-Host "  Press Win+R, type 'taskschd.msc', and look for '$taskName'"

Write-Host "`n"
pause