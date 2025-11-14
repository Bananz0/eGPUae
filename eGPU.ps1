# eGPU Auto Hot-Plug Manager
# This script continuously monitors for eGPU physical reconnection and automatically enables it
# Designed to run at startup and handle all eGPU hot-plug scenarios

<#
.SYNOPSIS
    eGPU Auto-Enable Tool - Automatically re-enables eGPU after hot-plugging on Windows

.DESCRIPTION
    This tool monitors your external GPU and automatically enables it whenever you reconnect it after safe-removal.
    It eliminates the need to manually enable the eGPU from Device Manager.

.NOTES
    File Name      : eGPU.ps1
    Prerequisite   : PowerShell 7.0 or later
    Requires Admin : Yes (for pnputil device enabling)
    Version        : 1.1.0
    Repository     : https://github.com/Bananz0/eGPUae
#>

# ===== CONFIGURATION =====
# Paths
$installPath = Join-Path $env:USERPROFILE ".egpu-manager"
$configPath = Join-Path $installPath "egpu-config.json"
$logPath = Join-Path $installPath "egpu-manager.log"
$lastUpdateCheckFile = Join-Path $installPath "last-update-check.txt"

# Polling and logging configuration
$pollInterval = 2  # seconds
$maxLogSizeKB = 500
$maxLogLines = 1000

# Update check configuration
$updateCheckInterval = 86400  # Check once per day (in seconds)

# Display sleep management
$savedDisplayTimeout = $null
$displaySleepManaged = $false
# =========================

# Logging function with automatic rotation
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"  # INFO, SUCCESS, WARNING, ERROR
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console (color-coded)
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
    
    # Append to log file
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
        
        # Check log size and rotate if needed
        $logFile = Get-Item $logPath -ErrorAction SilentlyContinue
        if ($logFile -and ($logFile.Length / 1KB) -gt $maxLogSizeKB) {
            # Read last N lines
            $allLines = Get-Content $logPath
            $linesToKeep = $allLines | Select-Object -Last $maxLogLines
            
            # Create backup of old log
            $backupPath = Join-Path $installPath "egpu-manager.old.log"
            if (Test-Path $backupPath) {
                Remove-Item $backupPath -Force
            }
            Move-Item $logPath $backupPath -Force
            
            # Write kept lines to new log
            $linesToKeep | Set-Content $logPath
            
            $savedKB = [math]::Round(($logFile.Length - (Get-Item $logPath).Length) / 1KB, 2)
            Add-Content -Path $logPath -Value "[$timestamp] [INFO] Log rotated. Saved ${savedKB}KB. Kept last $maxLogLines lines."
        }
    } catch {
        # Silently fail if logging doesn't work (don't break the script)
    }
}

# Manage display sleep settings
function Set-DisplaySleep {
    param(
        [bool]$Disable
    )
    
    try {
        if ($Disable) {
            # Get current setting
            $script:savedDisplayTimeout = (powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String "Current AC Power Setting Index:" | ForEach-Object { $_.ToString().Split(':')[1].Trim() })
            
            if ($script:savedDisplayTimeout -ne "0x00000000") {
                # Disable display sleep
                powercfg /change monitor-timeout-ac 0 | Out-Null
                $script:displaySleepManaged = $true
                Write-Log "Display sleep disabled (saved timeout: $script:savedDisplayTimeout seconds)" "INFO"
                return $true
            }
        } else {
            # Restore original setting
            if ($script:displaySleepManaged -and $script:savedDisplayTimeout) {
                $timeoutMinutes = [int]("0x" + $script:savedDisplayTimeout) / 60
                powercfg /change monitor-timeout-ac $timeoutMinutes | Out-Null
                Write-Log "Display sleep restored to $timeoutMinutes minutes" "INFO"
                $script:displaySleepManaged = $false
                return $true
            }
        }
    } catch {
        Write-Log "Failed to manage display sleep: $_" "WARNING"
    }
    
    return $false
}

# Check if external monitors are connected
function Test-ExternalMonitor {
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams | 
                    Where-Object { $_.Active -eq $true }
        
        # More than 1 active monitor = external monitor(s) present
        return ($monitors.Count -gt 1)
    } catch {
        Write-Log "Failed to check external monitors: $_" "WARNING"
        return $false
    }
}

# Show Windows Toast Notification
function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Type = "Info"
    )
    
    try {
        # Load WinRT assemblies (more robust approach from Toast Notification Script)
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        
        # Load the required WinRT types
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        
        # Use PowerShell app ID (works reliably without custom app registration)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        
        $toastXml = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$Title</text>
            <text>$Message</text>
        </binding>
    </visual>
    <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@
        
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($toastXml)
        
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        
        Write-Log "Notification shown: $Title" "INFO"
    } catch {
        Write-Log "Failed to show notification: $_" "INFO"
    }
}

# Check for updates (runs once per day)
function Check-ForUpdate {
    param($config)
    
    # Check if we should check for updates
    $shouldCheck = $true
    
    if (Test-Path $lastUpdateCheckFile) {
        try {
            $lastCheck = Get-Content $lastUpdateCheckFile | Get-Date
            $timeSinceCheck = (Get-Date) - $lastCheck
            
            if ($timeSinceCheck.TotalSeconds -lt $updateCheckInterval) {
                $shouldCheck = $false
            }
        } catch {
            $shouldCheck = $true
        }
    }
    
    if (-not $shouldCheck) {
        return
    }
    
    # Check if update checks are enabled
    if ($config.AutoUpdateCheck -eq $false) {
        return
    }
    
    # Update the last check time
    Get-Date | Set-Content $lastUpdateCheckFile -ErrorAction SilentlyContinue
    
    try {
        $currentVersion = if ($config.InstalledVersion) { $config.InstalledVersion } else { "1.0.0" }
        $updateUrl = "https://api.github.com/repos/Bananz0/eGPUae/releases/latest"
        
        $releaseInfo = Invoke-RestMethod -Uri $updateUrl -ErrorAction Stop -TimeoutSec 5
        $latestVersion = $releaseInfo.tag_name.TrimStart("v")
        
        # Simple version comparison
        $currentParts = $currentVersion.Split(".")
        $latestParts = $latestVersion.Split(".")
        
        $isNewer = $false
        for ($i = 0; $i -lt 3; $i++) {
            $curr = [int]$currentParts[$i]
            $latest = [int]$latestParts[$i]
            
            if ($latest -gt $curr) {
                $isNewer = $true
                break
            } elseif ($latest -lt $curr) {
                break
            }
        }
        
        if ($isNewer) {
            Show-Notification -Title "eGPU Manager Update Available" `
                             -Message "Version $latestVersion is available (you have $currentVersion). Run the installer to update." `
                             -Type "Info"
            
            Write-Log "Update available: v$currentVersion -> v$latestVersion" "WARNING"
        } else {
            Write-Log "Update check: Already on latest version (v$currentVersion)" "INFO"
        }
    } catch {
        Write-Log "Update check failed (will retry in 24h): $_" "INFO"
    }
}

function Get-eGPUState {
    param([string]$egpu_name)
    
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    
    if ($null -eq $egpu) {
        return "absent"
    }
    
    try {
        $problemCode = (Get-PnpDeviceProperty -InstanceId $egpu.InstanceId -KeyName "DEVPKEY_Device_ProblemCode" -ErrorAction Stop).Data
        
        if ($egpu.Status -eq "OK") {
            return "present-ok"
        } elseif ($egpu.Status -eq "Error") {
            if ($problemCode -eq 45) {
                return "absent"
            } else {
                return "present-disabled"
            }
        } else {
            return "absent"
        }
    } catch {
        return "absent"
    }
}

function Get-eGPUDevice {
    param([string]$egpu_name)
    return Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
}

function Enable-eGPU {
    param(
        [string]$egpu_name,
        [int]$MaxRetries = 3
    )
    
    $egpu = Get-eGPUDevice -egpu_name $egpu_name
    
    if ($null -eq $egpu) {
        Write-Log "ERROR: eGPU device not found" "ERROR"
        return $false
    }
    
    Write-Log "Device Details: Name=$($egpu.FriendlyName), Status=$($egpu.Status)" "INFO"
    
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Log "WARNING: Script is NOT running as Administrator!" "ERROR"
        return $false
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            Write-Log "Retry attempt $attempt/$MaxRetries..." "WARNING"
        }
        
        try {
            Write-Log "Using pnputil to enable device..." "INFO"
            $enableResult = & pnputil /enable-device "$($egpu.InstanceId)" 2>&1
            Write-Log "pnputil output: $enableResult" "INFO"
            Start-Sleep -Seconds 2
            
            $egpu = Get-eGPUDevice -egpu_name $egpu_name
            if ($null -ne $egpu -and $egpu.Status -eq "OK") {
                Write-Log "Device enabled successfully!" "SUCCESS"
                return $true
            }
            
            $currentStatus = if ($null -ne $egpu) { $egpu.Status } else { "NULL" }
            Write-Log "Enable attempted but status is: $currentStatus" "WARNING"
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
            
        } catch {
            Write-Log "ERROR on attempt $attempt : $_" "ERROR"
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
        }
    }
    
    return $false
}

# ===== MAIN SCRIPT START =====

Clear-Host
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  eGPU Auto Hot-Plug Manager" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

# Load configuration
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Config file not found at $configPath" -ForegroundColor Red
    Write-Host "Please run the installer script to configure your eGPU." -ForegroundColor Yellow
    Write-Host "Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}

try {
    $config = Get-Content $configPath | ConvertFrom-Json
    $egpu_name = $config.eGPU_Name
} catch {
    Write-Host "ERROR: Could not read config file: $_" -ForegroundColor Red
    Write-Host "Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}

if ([string]::IsNullOrEmpty($egpu_name)) {
    Write-Host "ERROR: eGPU_Name is not set in config" -ForegroundColor Red
    Write-Host "Please re-run the installer." -ForegroundColor Yellow
    Write-Host "Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}

Write-Host "eGPU: $egpu_name" -ForegroundColor White
Write-Host "Poll Interval: $pollInterval seconds" -ForegroundColor White
Write-Host "Log File: $logPath" -ForegroundColor White
Write-Host "Press Ctrl+C to stop.`n" -ForegroundColor Gray

Write-Log "=== eGPU Manager Started ===" "INFO"
Write-Log "eGPU Name: $egpu_name" "INFO"
Write-Log "Poll Interval: $pollInterval seconds" "INFO"
Write-Log "Version: $($config.InstalledVersion)" "INFO"

# Check for updates
Check-ForUpdate -config $config

# Get initial state
$script:lastKnownState = Get-eGPUState -egpu_name $egpu_name
$startupTime = Get-Date -Format 'HH:mm:ss'

switch ($script:lastKnownState) {
    "present-ok" {
        Write-Log "STARTUP: eGPU connected and enabled" "SUCCESS"
    }
    "present-disabled" {
        Write-Log "STARTUP: eGPU connected but disabled (safe-removed)" "WARNING"
        Write-Host "    Waiting for physical reconnection to auto-enable..." -ForegroundColor Gray
    }
    "absent" {
        Write-Log "STARTUP: eGPU not connected" "INFO"
        Write-Host "    Waiting for eGPU to be plugged in..." -ForegroundColor Gray
    }
}

Write-Host "`n--- Monitoring started ---`n" -ForegroundColor Gray

$checkCount = 0
$lastHeartbeat = Get-Date

# Main monitoring loop
while ($true) {
    Start-Sleep -Seconds $pollInterval
    $checkCount++
    
    $currentState = Get-eGPUState -egpu_name $egpu_name
    $stateChanged = $currentState -ne $script:lastKnownState
    
    if ($stateChanged) {
        Write-Log "State change: $script:lastKnownState -> $currentState" "INFO"
        
        # Handle state transitions
        if ($script:lastKnownState -match "present" -and $currentState -eq "absent") {
            Write-Log "eGPU physically unplugged" "WARNING"
        }
        elseif ($script:lastKnownState -eq "absent" -and $currentState -match "present") {
            Write-Log "eGPU physically reconnected" "INFO"
            
            if ($currentState -eq "present-disabled") {
                if (Enable-eGPU -egpu_name $egpu_name) {
                    Write-Log "eGPU enabled successfully via auto-enable" "SUCCESS"
                    Show-Notification -Title "eGPU Enabled" -Message "Your $egpu_name has been automatically enabled and is ready to use."
                    
                    # Check if external monitors are connected and manage display sleep
                    if (Test-ExternalMonitor) {
                        Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                        Set-DisplaySleep -Disable $true
                    }
                    
                    $currentState = "present-ok"
                } else {
                    Write-Log "Failed to enable eGPU" "ERROR"
                    Show-Notification -Title "eGPU Enable Failed" -Message "Could not automatically enable $egpu_name. Please check Device Manager."
                }
            }
            elseif ($currentState -eq "present-ok") {
                Write-Log "eGPU reconnected and already enabled" "SUCCESS"
                
                # Check if external monitors are connected and manage display sleep
                if (Test-ExternalMonitor) {
                    Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                    Set-DisplaySleep -Disable $true
                }
            }
        }
        elseif ($script:lastKnownState -eq "present-ok" -and $currentState -eq "present-disabled") {
            Write-Log "eGPU disabled (safe-removed)" "WARNING"
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "present-ok") {
            Write-Log "eGPU enabled manually or by another process" "INFO"
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "absent") {
            Write-Log "eGPU physically unplugged (from disabled state)" "WARNING"
            
            # Restore display sleep when eGPU is unplugged
            if ($script:displaySleepManaged) {
                Write-Log "Restoring display sleep settings" "INFO"
                Set-DisplaySleep -Disable $false
            }
        }
        elseif ($script:lastKnownState -eq "absent" -and $currentState -eq "present-disabled") {
            Write-Log "eGPU reconnected (disabled), attempting auto-enable..." "INFO"
            
            Start-Sleep -Seconds 2
            
            $enableResult = Enable-eGPU -egpu_name $egpu_name -MaxRetries 5
            
            if ($enableResult) {
                Write-Log "eGPU enabled successfully after reconnection" "SUCCESS"
                Show-Notification -Title "eGPU Enabled" -Message "Your $egpu_name has been automatically enabled and is ready to use."
                
                Start-Sleep -Seconds 1
                $currentState = Get-eGPUState -egpu_name $egpu_name
                
                if ($currentState -eq "present-ok") {
                    Write-Log "Verified: eGPU is active and operational" "SUCCESS"
                    
                    # Check if external monitors are connected and manage display sleep
                    if (Test-ExternalMonitor) {
                        Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                        Set-DisplaySleep -Disable $true
                    }
                } else {
                    Write-Log "Warning: Enable succeeded but state is $currentState" "WARNING"
                }
            } else {
                Write-Log "Failed to enable eGPU after multiple attempts" "ERROR"
                Show-Notification -Title "eGPU Enable Failed" -Message "Could not automatically enable $egpu_name. Please check Device Manager."
            }
        }
    }
    
    # Heartbeat every 30 seconds
    if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 30) {
        $statusEmoji = switch ($currentState) {
            "present-ok" { "✓" }
            "present-disabled" { "⊗" }
            "absent" { "○" }
            default { "○" }
        }
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Heartbeat $statusEmoji - State: $currentState" -ForegroundColor DarkGray
        $lastHeartbeat = Get-Date
    }
    
    $script:lastKnownState = $currentState
}