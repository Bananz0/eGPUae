# eGPU Auto Re-enable Script
# This script continuously monitors for eGPU physical reconnection and automatically enables it
# Designed to run at startup and handle all eGPU hot-plug scenarios

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

 $logPath = Join-Path $installPath "egpu-manager.log"
 $maxLogSize = 500KB

function Write-Log {
    param(
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] $Message"
    
    # Write to console
    Write-Log $logEntry -ForegroundColor $Color
    
    # Write to log file
    try {
        # Check if log file exceeds max size and rotate if needed
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt $maxLogSize) {
            $backupPath = Join-Path $installPath "egpu-manager.backup.log"
            Move-Item $logPath $backupPath -Force
        }
        
        Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Failed to write to log file: $_" -ForegroundColor Red
    }
}

function Check-ForUpdate {
    $currentVersion = $config.InstalledVersion
    $updateUrl = "https://api.github.com/repos/bananz0/eGPUae/releases/latest"
    
    try {
        $releaseInfo = Invoke-RestMethod -Uri $updateUrl -ErrorAction Stop
        $latestVersion = $releaseInfo.tag_name.Trim("v")
        
        if ($latestVersion -gt $currentVersion) {
            Write-Log "Update available: $latestVersion (you have $currentVersion)" -ForegroundColor Yellow
            Write-Log "Download from: $($releaseInfo.html_url)" -ForegroundColor Yellow
            return $true
        }
    } catch {
        Write-Log "Failed to check for updates: $_" -ForegroundColor Red
    }
    
    return $false
}

# ===== CONFIGURATION =====
# Paths
$installPath = Join-Path $env:USERPROFILE ".egpu-manager"
$configPath = Join-Path $installPath "egpu-config.json"

# How often to check for changes (in seconds)
$pollInterval = 2

# Load eGPU name from config file
$egpu_name = $null

if (-not (Test-Path $configPath)) {
    Write-Log "[$startupTime] ERROR: Config file not found at $configPath" -ForegroundColor Red
    Write-Log "    Please run the installer script again to configure your eGPU." -ForegroundColor Yellow
    Write-Log "    Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}

try {
    $config = Get-Content $configPath | ConvertFrom-Json
    $egpu_name = $config.eGPU_Name
} catch {
    Write-Log "[$startupTime] ERROR: Could not read or parse config file $configPath" -ForegroundColor Red
    Write-Log "    Error: $_" -ForegroundColor Red
    Write-Log "    Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}

if ([string]::IsNullOrEmpty($egpu_name)) {
    Write-Log "[$startupTime] ERROR: eGPU_Name is not set in $configPath" -ForegroundColor Red
    Write-Log "    Please try re-running the installer." -ForegroundColor Yellow
    Write-Log "    Exiting in 20 seconds..." -ForegroundColor Gray
    Start-Sleep -Seconds 20
    exit
}
# =========================

# Track previous state
$script:lastKnownState = $null  # Will store: "present-ok", "present-disabled", or "absent"

function Get-eGPUState {
    # Get eGPU device info
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    
    if ($null -eq $egpu) {
        return "absent"
    }
    
    try {
        # Get multiple properties to make a more informed decision
        $problemCode = (Get-PnpDeviceProperty -InstanceId $egpu.InstanceId -KeyName "DEVPKEY_Device_ProblemCode" -ErrorAction Stop).Data
        $devicePresence = (Get-PnpDeviceProperty -InstanceId $egpu.InstanceId -KeyName "DEVPKEY_Device_Presence" -ErrorAction SilentlyContinue).Data
        
        # More comprehensive state detection logic
        if ($egpu.Status -eq "OK") {
            return "present-ok"
        } elseif ($egpu.Status -eq "Error") {
            if ($problemCode -eq 45 -or ($null -ne $devicePresence -and $devicePresence -eq 0)) {
                return "absent"
            } elseif ($problemCode -eq 22) {
                return "present-disabled"
            } else {
                return "present-error"
            }
        } else {
            # Additional check for "Unknown" status
            if ($null -ne $devicePresence -and $devicePresence -eq 1) {
                return "present-unknown"
            } else {
                return "absent"
            }
        }
    } catch {
        return "absent"
    }
}

function Get-eGPUDevice {
    return Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
}

function Enable-eGPU {
    param([int]$MaxRetries = 3)
    
    $egpu = Get-eGPUDevice
    
    if ($null -eq $egpu) {
        Write-Log "    ERROR: eGPU device not found" -ForegroundColor Red
        return $false
    }
    
    Write-Log "    Device Details:" -ForegroundColor Cyan
    Write-Log "      Name: $($egpu.FriendlyName)"
    Write-Log "      InstanceID: $($egpu.InstanceId)"
    Write-Log "      Status: $($egpu.Status)"
    
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log "      Running as Admin: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Red" })
    
    if (-not $isAdmin) {
        Write-Log "    ⚠ WARNING: Script is NOT running as Administrator!" -ForegroundColor Red
        return $false
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            Write-Log "    Retry attempt $attempt/$MaxRetries..." -ForegroundColor Yellow
        }
        
        try {
            # Use pnputil - the most reliable method
            Write-Log "    Using pnputil to enable device..." -ForegroundColor Gray
            $enableResult = & pnputil /enable-device "$($egpu.InstanceId)" 2>&1
            Write-Log "    pnputil output: $enableResult" -ForegroundColor Gray
            Start-Sleep -Seconds 2
            
            $egpu = Get-eGPUDevice
            if ($null -ne $egpu -and $egpu.Status -eq "OK") {
                Write-Log "    ✓ Device enabled successfully!" -ForegroundColor Green
                return $true
            }
            
            $currentStatus = if ($null -ne $egpu) { $egpu.Status } else { "NULL" }
            Write-Log "    Enable attempted but status is: $currentStatus" -ForegroundColor Yellow
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
            
        } catch {
            Write-Log "    ERROR on attempt $attempt : $_" -ForegroundColor Red
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
        }
    }
    
    return $false
}

Clear-Host
Write-Log "=======================================" -ForegroundColor Cyan
Write-Log "  eGPU Auto Hot-Plug Manager" -ForegroundColor Cyan
Write-Log "=======================================" -ForegroundColor Cyan
Write-Log "eGPU: $egpu_name"
Write-Log "Poll Interval: $pollInterval seconds"
Write-Log "Monitoring Mode: Continuous"
Write-Log "Press Ctrl+C to stop.`n"

# Get initial state
$script:lastKnownState = Get-eGPUState
$startupTime = Get-Date -Format 'HH:mm:ss'

switch ($script:lastKnownState) {
    "present-ok" {
        Write-Log "[$startupTime] STARTUP: eGPU connected and enabled ✓" -ForegroundColor Green
    }
    "present-disabled" {
        Write-Log "[$startupTime] STARTUP: eGPU connected but disabled (safe-removed)" -ForegroundColor Yellow
        Write-Log "    Waiting for physical reconnection to auto-enable..."
    }
    "absent" {
        Write-Log "[$startupTime] STARTUP: eGPU not connected" -ForegroundColor DarkGray
        Write-Log "    Waiting for eGPU to be plugged in..."
    }
}

Write-Log "`n--- Monitoring started ---`n"

$checkCount = 0
$lastHeartbeat = Get-Date

# Main monitoring loop
while ($true) {
    Start-Sleep -Seconds $pollInterval
    $checkCount++
    
    # Get current state
    $currentState = Get-eGPUState
    
    # Detect state changes
    $stateChanged = $currentState -ne $script:lastKnownState
    
    if ($stateChanged) {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        Write-Log "`n[$timestamp] STATE CHANGE DETECTED:" -ForegroundColor Cyan
        Write-Log "    Was: $script:lastKnownState"
        Write-Log "    Now: $currentState"
        
        # Handle different state transitions
        if ($script:lastKnownState -match "present" -and $currentState -eq "absent") {
            Write-Log "`n    >>> eGPU PHYSICALLY UNPLUGGED <<<" -ForegroundColor Red
            Write-Log "    Waiting for reconnection...`n"
        }
        elseif ($script:lastKnownState -eq "absent" -and $currentState -match "present") {
            Write-Log "`n    >>> eGPU PHYSICALLY RECONNECTED <<<" -ForegroundColor Yellow
            
            if ($currentState -eq "present-disabled") {
                Write-Log "    Status: Disabled (from previous safe-removal)"
                Write-Log "    Action: Enabling eGPU..." -ForegroundColor Green
                
                if (Enable-eGPU) {
                    Write-Log "    ✓ eGPU ENABLED SUCCESSFULLY!" -ForegroundColor Green
                    $currentState = "present-ok"  # Update state after enabling
                } else {
                    Write-Log "    ✗ Failed to enable eGPU" -ForegroundColor Red
                }
            }
            elseif ($currentState -eq "present-ok") {
                Write-Log "    Status: Already enabled ✓" -ForegroundColor Green
                Write-Log "    Action: No action needed"
            }
            Write-Log ""
        }
        elseif ($script:lastKnownState -eq "present-ok" -and $currentState -eq "present-disabled") {
            Write-Log "`n    >>> eGPU DISABLED (Safe-removed via NVIDIA Control Panel) <<<" -ForegroundColor Yellow
            Write-Log "    Waiting for physical unplug/replug to auto-enable...`n"
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "present-ok") {
            Write-Log "`n    >>> eGPU ENABLED (manually or by another process) <<<" -ForegroundColor Green
            Write-Log ""
        }
        # Handle transition to absent (unknown state = unplugged)
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "absent") {
            Write-Log "`n    >>> eGPU PHYSICALLY UNPLUGGED <<<" -ForegroundColor Red
            Write-Log "    Waiting for reconnection...`n"
        }
        # Handle reconnection from absent back to disabled
        elseif ($script:lastKnownState -eq "absent" -and $currentState -eq "present-disabled") {
            Write-Log "`n    >>> eGPU PHYSICALLY RECONNECTED <<<" -ForegroundColor Yellow
            Write-Log "    Status: Device reconnected but disabled"
            Write-Log "    Action: Enabling eGPU..." -ForegroundColor Green
            
            # Wait for device to fully stabilize
            Start-Sleep -Seconds 2
            
            $enableResult = Enable-eGPU -MaxRetries 5
            
            if ($enableResult) {
                Write-Log "    ✓ eGPU ENABLED SUCCESSFULLY!" -ForegroundColor Green
                # Force a state refresh to confirm
                Start-Sleep -Seconds 1
                $currentState = Get-eGPUState
                if ($currentState -eq "present-ok") {
                    Write-Log "    ✓ Verified: eGPU is now active and operational" -ForegroundColor Green
                } else {
                    Write-Log "    ⚠ Warning: Enable command succeeded but device still shows as: $currentState" -ForegroundColor Yellow
                    Write-Log "    This may require manual intervention or a driver restart" -ForegroundColor Yellow
                }
            } else {
                Write-Log "    ✗ FAILED to enable eGPU after multiple attempts" -ForegroundColor Red
                Write-Log "    You may need to enable it manually from Device Manager" -ForegroundColor Yellow
            }
            Write-Log ""
        }
    }
    
    # Heartbeat every 30 seconds to show script is still running
    if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 30) {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $statusEmoji = switch ($currentState) {
            "present-ok" { "✓" }
            "present-disabled" { "⊗" }
            "absent" { "○" }
            default { "○" }
        }
        
        Write-Log "[$timestamp] Heartbeat $statusEmoji - State: $currentState" -ForegroundColor DarkGray
        $lastHeartbeat = Get-Date
    }
    
    # Update tracking
    $script:lastKnownState = $currentState
}