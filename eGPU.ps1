# eGPU Auto Re-enable Script (Enhanced Detection)
# This script continuously monitors for eGPU physical reconnection and automatically enables it
# Designed to run at startup and handle all eGPU hot-plug scenarios

# ===== CONFIGURATION =====
# Set your eGPU name (change this to match your GPU)
$egpu_name = "NVIDIA GeForce RTX 5070 Ti"
# How often to check for changes (in seconds)
$pollInterval = 2
# =========================

# Track previous state
$script:lastKnownState = $null  # Will store: "present-ok", "present-disabled", or "absent"

function Get-eGPUState {
    # Get eGPU device info
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    
    if ($null -eq $egpu) {
        return "absent"
    }
    
    # Check if device is actually accessible (not just cached)
    # A truly connected device will have a valid problem code
    try {
        $problemCode = (Get-PnpDeviceProperty -InstanceId $egpu.InstanceId -KeyName "DEVPKEY_Device_ProblemCode" -ErrorAction Stop).Data
        
        # If we can query it and it's working (problem code 0) or disabled (problem code 22)
        if ($egpu.Status -eq "OK") {
            return "present-ok"
        } elseif ($egpu.Status -eq "Error") {
            # Check if it's actually there or just a ghost entry
            # Problem code 22 = disabled, 45 = not connected
            if ($problemCode -eq 45) {
                return "absent"
            } else {
                return "present-disabled"
            }
        } else {
            # Treat "unknown" status as absent (device unplugged but cached)
            return "absent"
        }
    } catch {
        # If we can't query properties, device is likely not actually present
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
        Write-Host "    ERROR: eGPU device not found" -ForegroundColor Red
        return $false
    }
    
    Write-Host "    Device Details:" -ForegroundColor Cyan
    Write-Host "      Name: $($egpu.FriendlyName)"
    Write-Host "      InstanceID: $($egpu.InstanceId)"
    Write-Host "      Status: $($egpu.Status)"
    
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Host "      Running as Admin: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Red" })
    
    if (-not $isAdmin) {
        Write-Host "    ⚠ WARNING: Script is NOT running as Administrator!" -ForegroundColor Red
        return $false
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            Write-Host "    Retry attempt $attempt/$MaxRetries..." -ForegroundColor Yellow
        }
        
        try {
            # Use pnputil - the most reliable method
            Write-Host "    Using pnputil to enable device..." -ForegroundColor Gray
            $enableResult = & pnputil /enable-device "$($egpu.InstanceId)" 2>&1
            Write-Host "    pnputil output: $enableResult" -ForegroundColor Gray
            Start-Sleep -Seconds 2
            
            $egpu = Get-eGPUDevice
            if ($null -ne $egpu -and $egpu.Status -eq "OK") {
                Write-Host "    ✓ Device enabled successfully!" -ForegroundColor Green
                return $true
            }
            
            $currentStatus = if ($null -ne $egpu) { $egpu.Status } else { "NULL" }
            Write-Host "    Enable attempted but status is: $currentStatus" -ForegroundColor Yellow
            
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
            
        } catch {
            Write-Host "    ERROR on attempt $attempt : $_" -ForegroundColor Red
            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
        }
    }
    
    return $false
}

Clear-Host
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  eGPU Auto Hot-Plug Manager" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "eGPU: $egpu_name"
Write-Host "Poll Interval: $pollInterval seconds"
Write-Host "Monitoring Mode: Continuous"
Write-Host "Press Ctrl+C to stop.`n"

# Get initial state
$script:lastKnownState = Get-eGPUState
$startupTime = Get-Date -Format 'HH:mm:ss'

switch ($script:lastKnownState) {
    "present-ok" {
        Write-Host "[$startupTime] STARTUP: eGPU connected and enabled ✓" -ForegroundColor Green
    }
    "present-disabled" {
        Write-Host "[$startupTime] STARTUP: eGPU connected but disabled (safe-removed)" -ForegroundColor Yellow
        Write-Host "    Waiting for physical reconnection to auto-enable..."
    }
    "absent" {
        Write-Host "[$startupTime] STARTUP: eGPU not connected" -ForegroundColor DarkGray
        Write-Host "    Waiting for eGPU to be plugged in..."
    }
}

Write-Host "`n--- Monitoring started ---`n"

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
        Write-Host "`n[$timestamp] STATE CHANGE DETECTED:" -ForegroundColor Cyan
        Write-Host "    Was: $script:lastKnownState"
        Write-Host "    Now: $currentState"
        
        # Handle different state transitions
        if ($script:lastKnownState -match "present" -and $currentState -eq "absent") {
            Write-Host "`n    >>> eGPU PHYSICALLY UNPLUGGED <<<" -ForegroundColor Red
            Write-Host "    Waiting for reconnection...`n"
        }
        elseif ($script:lastKnownState -eq "absent" -and $currentState -match "present") {
            Write-Host "`n    >>> eGPU PHYSICALLY RECONNECTED <<<" -ForegroundColor Yellow
            
            if ($currentState -eq "present-disabled") {
                Write-Host "    Status: Disabled (from previous safe-removal)"
                Write-Host "    Action: Enabling eGPU..." -ForegroundColor Green
                
                if (Enable-eGPU) {
                    Write-Host "    ✓ eGPU ENABLED SUCCESSFULLY!" -ForegroundColor Green
                    $currentState = "present-ok"  # Update state after enabling
                } else {
                    Write-Host "    ✗ Failed to enable eGPU" -ForegroundColor Red
                }
            }
            elseif ($currentState -eq "present-ok") {
                Write-Host "    Status: Already enabled ✓" -ForegroundColor Green
                Write-Host "    Action: No action needed"
            }
            Write-Host ""
        }
        elseif ($script:lastKnownState -eq "present-ok" -and $currentState -eq "present-disabled") {
            Write-Host "`n    >>> eGPU DISABLED (Safe-removed via NVIDIA Control Panel) <<<" -ForegroundColor Yellow
            Write-Host "    Waiting for physical unplug/replug to auto-enable...`n"
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "present-ok") {
            Write-Host "`n    >>> eGPU ENABLED (manually or by another process) <<<" -ForegroundColor Green
            Write-Host ""
        }
        # Handle transition to absent (unknown state = unplugged)
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "absent") {
            Write-Host "`n    >>> eGPU PHYSICALLY UNPLUGGED <<<" -ForegroundColor Red
            Write-Host "    Waiting for reconnection...`n"
        }
        # Handle reconnection from absent back to disabled
        elseif ($script:lastKnownState -eq "absent" -and $currentState -eq "present-disabled") {
            Write-Host "`n    >>> eGPU PHYSICALLY RECONNECTED <<<" -ForegroundColor Yellow
            Write-Host "    Status: Device reconnected but disabled"
            Write-Host "    Action: Enabling eGPU..." -ForegroundColor Green
            
            # Wait for device to fully stabilize
            Start-Sleep -Seconds 2
            
            $enableResult = Enable-eGPU -MaxRetries 5
            
            if ($enableResult) {
                Write-Host "    ✓ eGPU ENABLED SUCCESSFULLY!" -ForegroundColor Green
                # Force a state refresh to confirm
                Start-Sleep -Seconds 1
                $currentState = Get-eGPUState
                if ($currentState -eq "present-ok") {
                    Write-Host "    ✓ Verified: eGPU is now active and operational" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠ Warning: Enable command succeeded but device still shows as: $currentState" -ForegroundColor Yellow
                    Write-Host "    This may require manual intervention or a driver restart" -ForegroundColor Yellow
                }
            } else {
                Write-Host "    ✗ FAILED to enable eGPU after multiple attempts" -ForegroundColor Red
                Write-Host "    You may need to enable it manually from Device Manager" -ForegroundColor Yellow
            }
            Write-Host ""
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
        
        Write-Host "[$timestamp] Heartbeat $statusEmoji - State: $currentState" -ForegroundColor DarkGray
        $lastHeartbeat = Get-Date
    }
    
    # Update tracking
    $script:lastKnownState = $currentState
}