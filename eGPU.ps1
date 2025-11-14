# eGPU Auto Re-enable Script
# This script monitors for eGPU physical reconnection and automatically enables it
# Only re-enables after the eGPU has been physically disconnected and reconnected

Unregister-Event -SourceIdentifier eGPUMonitor -ErrorAction SilentlyContinue

# Set your eGPU name
$egpu_name = "NVIDIA GeForce RTX 3080"

# Track whether eGPU was physically present in last check
$script:egpuWasPresent = $false

function Test-eGPUPresence {
    # Check if eGPU exists in system at all (regardless of status)
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    return ($null -ne $egpu)
}

function Enable-eGPUIfNeeded {
    param([bool]$PhysicalReconnection = $false)
    
    Write-Host "Checking eGPU status..."
    
    # Find eGPU by name (even if disabled)
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    
    if ($null -ne $egpu) {
        $egpu_status = $egpu.Status
        $egpu_id = $egpu.InstanceId
        
        Write-Host "eGPU found: $($egpu.FriendlyName)"
        Write-Host "Current status: $egpu_status"
        
        # Only enable if it's a physical reconnection AND the device is disabled
        if ($PhysicalReconnection -and $egpu_status -eq "Error") {
            Write-Host ">>> Physical reconnection detected! Enabling eGPU..."
            try {
                Enable-PnpDevice -InstanceId $egpu_id -Confirm:$false
                Write-Host ">>> eGPU enabled successfully!"
            } catch {
                Write-Host ">>> Failed to enable eGPU: $_"
            }
        }
        elseif ($egpu_status -eq "OK") {
            Write-Host "eGPU is already enabled."
        }
        elseif ($egpu_status -eq "Error" -and -not $PhysicalReconnection) {
            Write-Host "eGPU is disabled (waiting for physical reconnection to auto-enable)."
        }
    }
    else {
        Write-Host "eGPU not detected in system."
    }
}

Write-Host "=== eGPU Auto Re-enable Script Started ==="
Write-Host "Monitoring for physical eGPU reconnection..."
Write-Host "eGPU Name: $egpu_name"
Write-Host "Press Ctrl+C to stop.`n"

# Initialize tracking: check if eGPU is present at startup
$script:egpuWasPresent = Test-eGPUPresence
if ($script:egpuWasPresent) {
    Write-Host "[STARTUP] eGPU is currently PRESENT"
} else {
    Write-Host "[STARTUP] eGPU is currently ABSENT"
}

# Check initial status (but don't auto-enable on script start)
Enable-eGPUIfNeeded -PhysicalReconnection $false

Write-Host "`n--- Waiting for device events ---`n"

# Register for device change events
Register-WmiEvent -Class Win32_DeviceChangeEvent -SourceIdentifier eGPUMonitor

# Monitor for device changes
do {
    $newEvent = Wait-Event -SourceIdentifier eGPUMonitor
    $eventType = $newEvent.SourceEventArgs.NewEvent.EventType
    
    $eventTypeName = switch($eventType) {
        1 {"Configuration changed"}
        2 {"Device arrival"}
        3 {"Device removal"}
        4 {"Docking"}
        default {"Unknown ($eventType)"}
    }
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Device Event: $eventTypeName"
    
    # Check current presence
    $egpuIsPresent = Test-eGPUPresence
    
    # Show current state
    if ($egpuIsPresent) {
        Write-Host "  Current state: eGPU PRESENT"
    } else {
        Write-Host "  Current state: eGPU ABSENT"
    }
    
    if ($script:egpuWasPresent) {
        Write-Host "  Previous state: eGPU was PRESENT"
    } else {
        Write-Host "  Previous state: eGPU was ABSENT"
    }
    
    # Detect physical reconnection: was absent, now present
    $physicalReconnection = (-not $script:egpuWasPresent) -and $egpuIsPresent
    
    # Detect physical removal: was present, now absent
    $physicalRemoval = $script:egpuWasPresent -and (-not $egpuIsPresent)
    
    if ($physicalRemoval) {
        Write-Host "  >>> PHYSICAL REMOVAL DETECTED <<<"
    }
    
    if ($physicalReconnection) {
        Write-Host "  >>> PHYSICAL RECONNECTION DETECTED <<<"
    }
    
    # Try to enable eGPU only if it's a physical reconnection
    Enable-eGPUIfNeeded -PhysicalReconnection $physicalReconnection
    
    # Update tracking state
    $script:egpuWasPresent = $egpuIsPresent
    
    Remove-Event -SourceIdentifier eGPUMonitor
    
} while ($true)

# Cleanup on exit
Unregister-Event -SourceIdentifier eGPUMonitor -ErrorAction SilentlyContinue