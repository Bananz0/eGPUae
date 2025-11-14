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
            return "present-unknown"
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
    $egpu = Get-eGPUDevice
    
    if ($null -ne $egpu) {
        try {
            Enable-PnpDevice -InstanceId $egpu.InstanceId -Confirm:$false -ErrorAction Stop
            return $true
        } catch {
            Write-Host "    ERROR: Failed to enable - $_" -ForegroundColor Red
            return $false
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
    }
    
    # Heartbeat every 30 seconds to show script is still running
    if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 30) {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $statusEmoji = switch ($currentState) {
            "present-ok" { "✓" }
            "present-disabled" { "⊗" }
            "absent" { "○" }
            default { "?" }
        }
        
        Write-Host "[$timestamp] Heartbeat $statusEmoji - State: $currentState" -ForegroundColor DarkGray
        $lastHeartbeat = Get-Date
    }
    
    # Update tracking
    $script:lastKnownState = $currentState
}