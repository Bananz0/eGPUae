# eGPU Auto Re-enable Script
# This script monitors for eGPU physical reconnection and automatically enables it
# Only re-enables after the eGPU has been physically disconnected and reconnected

Unregister-Event -SourceIdentifier eGPUMonitor -ErrorAction SilentlyContinue

# Set your eGPU name
$egpu_name = "NVIDIA GeForce RTX 5070 Ti"

# Track whether eGPU was physically present in last check
$script:egpuWasPresent = $false

function Check-eGPUPresence {
    # Check if eGPU exists in system at all (regardless of status)
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    return ($egpu -ne $null)
}

function Enable-eGPU {
    param([bool]$PhysicalReconnection = $false)
    
    Write-Host "Checking eGPU status..."
    
    # Find eGPU by name (even if disabled)
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    
    if ($egpu) {
        $egpu_status = $egpu.Status
        $egpu_id = $egpu.InstanceId
        
        Write-Host "eGPU found: $($egpu.FriendlyName)"
        Write-Host "Current status: $egpu_status"
        
        # Only enable if it's a physical reconnection AND the device is disabled
        if ($PhysicalReconnection -and $egpu_status -eq "Error") {
            Write-Host "Physical reconnection detected! Enabling eGPU..."
            Enable-PnpDevice -InstanceId $egpu_id -Confirm:$false
            Write-Host "eGPU enabled successfully!"
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

Write-Host "eGPU Auto Re-enable Script Started!"
Write-Host "Monitoring for physical eGPU reconnection..."
Write-Host "Press Ctrl+C to stop.`n"

# Initialize tracking: check if eGPU is present at startup
$script:egpuWasPresent = Check-eGPUPresence
if ($script:egpuWasPresent) {
    Write-Host "eGPU detected at startup."
} else {
    Write-Host "eGPU not present at startup."
}

# Check initial status (but don't auto-enable on script start)
Enable-eGPU -PhysicalReconnection $false

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
    }
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Event detected: $eventTypeName"
    
    # Check current presence
    $egpuIsPresent = Check-eGPUPresence
    
    # Detect physical reconnection: was absent, now present
    $physicalReconnection = (-not $script:egpuWasPresent) -and $egpuIsPresent
    
    if ($physicalReconnection) {
        Write-Host "*** Physical reconnection detected! ***"
    }
    
    # Try to enable eGPU only if it's a physical reconnection
    Enable-eGPU -PhysicalReconnection $physicalReconnection
    
    # Update tracking state
    $script:egpuWasPresent = $egpuIsPresent
    
    Remove-Event -SourceIdentifier eGPUMonitor
    
} while ($true)

# Cleanup on exit
Unregister-Event -SourceIdentifier eGPUMonitor -ErrorAction SilentlyContinue