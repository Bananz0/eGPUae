# eGPU Auto Re-enable Script (Polling Version)
# This script continuously monitors for eGPU physical reconnection and automatically enables it
# Only re-enables after the eGPU has been physically disconnected and reconnected

# ===== CONFIGURATION =====
# Set your eGPU name (change this to match your GPU)
$egpu_name = "NVIDIA GeForce RTX 5070 Ti"
# How often to check for changes (in seconds)
$pollInterval = 2
# =========================

# Track whether eGPU was physically present in last check
$script:egpuWasPresent = $false

function Test-eGPUPresence {
    # Check if eGPU exists in system at all (regardless of status)
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    return ($null -ne $egpu)
}

function Get-eGPUInfo {
    # Get full eGPU information
    $egpu = Get-PnpDevice | Where-Object {$_.FriendlyName -like "*$egpu_name*"}
    return $egpu
}

function Enable-eGPUIfNeeded {
    param([bool]$PhysicalReconnection = $false)
    
    # Find eGPU by name (even if disabled)
    $egpu = Get-eGPUInfo
    
    if ($null -ne $egpu) {
        $egpu_status = $egpu.Status
        $egpu_id = $egpu.InstanceId
        
        # Only enable if it's a physical reconnection AND the device is disabled
        if ($PhysicalReconnection -and $egpu_status -eq "Error") {
            Write-Host ">>> ENABLING eGPU NOW..."
            try {
                Enable-PnpDevice -InstanceId $egpu_id -Confirm:$false
                Write-Host ">>> eGPU ENABLED SUCCESSFULLY!" -ForegroundColor Green
                return "Enabled"
            } catch {
                Write-Host ">>> FAILED to enable eGPU: $_" -ForegroundColor Red
                return "Failed"
            }
        }
        elseif ($egpu_status -eq "OK") {
            return "Already OK"
        }
        elseif ($egpu_status -eq "Error" -and -not $PhysicalReconnection) {
            return "Disabled (waiting)"
        }
    }
    return "Not Present"
}

Clear-Host
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "  eGPU Auto Re-enable Script (Polling)" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "eGPU Name: $egpu_name"
Write-Host "Poll Interval: $pollInterval seconds"
Write-Host "Press Ctrl+C to stop.`n"

# Initialize tracking: check if eGPU is present at startup
$script:egpuWasPresent = Test-eGPUPresence
$egpuInfo = Get-eGPUInfo

if ($script:egpuWasPresent) {
    Write-Host "[STARTUP] eGPU Status: PRESENT - $($egpuInfo.Status)" -ForegroundColor Green
} else {
    Write-Host "[STARTUP] eGPU Status: ABSENT" -ForegroundColor Yellow
}

Write-Host "`n--- Monitoring started ---`n"

$checkCount = 0

# Main monitoring loop
while ($true) {
    Start-Sleep -Seconds $pollInterval
    $checkCount++
    
    # Check current presence
    $egpuIsPresent = Test-eGPUPresence
    $egpuInfo = Get-eGPUInfo
    
    # Detect physical reconnection: was absent, now present
    $physicalReconnection = (-not $script:egpuWasPresent) -and $egpuIsPresent
    
    # Detect physical removal: was present, now absent
    $physicalRemoval = $script:egpuWasPresent -and (-not $egpuIsPresent)
    
    # Only show output when there's a change or action
    if ($physicalRemoval) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline
        Write-Host ">>> eGPU PHYSICALLY REMOVED <<<" -ForegroundColor Red
        Write-Host "    Waiting for reconnection...`n"
    }
    
    if ($physicalReconnection) {
        Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline
        Write-Host ">>> eGPU PHYSICALLY RECONNECTED <<<" -ForegroundColor Yellow
        Write-Host "    Device Status: $($egpuInfo.Status)"
        
        $result = Enable-eGPUIfNeeded -PhysicalReconnection $true
        
        if ($result -eq "Enabled") {
            Write-Host "    Action: Device was disabled, now enabled!" -ForegroundColor Green
        } elseif ($result -eq "Already OK") {
            Write-Host "    Action: Device is already enabled, no action needed." -ForegroundColor Cyan
        } elseif ($result -eq "Failed") {
            Write-Host "    Action: Failed to enable device!" -ForegroundColor Red
        }
        Write-Host ""
    }
    
    # Silent status check - only show heartbeat every 30 checks (1 minute if polling every 2 seconds)
    if ($checkCount % 30 -eq 0) {
        $statusSymbol = if ($egpuIsPresent) { "●" } else { "○" }
        $statusColor = if ($egpuIsPresent) { "Green" } else { "DarkGray" }
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Heartbeat: $statusSymbol " -ForegroundColor $statusColor -NoNewline
        if ($egpuIsPresent -and $null -ne $egpuInfo) {
            Write-Host "eGPU present - Status: $($egpuInfo.Status)" -ForegroundColor $statusColor
        } else {
            Write-Host "eGPU absent" -ForegroundColor $statusColor
        }
    }
    
    # Update tracking state
    $script:egpuWasPresent = $egpuIsPresent
}