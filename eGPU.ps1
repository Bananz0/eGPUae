# eGPU Auto Hot-Plug Manager
# This script continuously monitors for eGPU physical reconnection and automatically enables it
# Designed to run at startup and handle all eGPU hot-plug scenarios

# VERSION CONSTANT - Update this when releasing new versions
$SCRIPT_VERSION = "2.0.0"

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
    Version        : 2.0.0
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

# Runtime state file for crash recovery
$runtimeStatePath = Join-Path $installPath "runtime-state.json"

# Update check configuration
$updateCheckInterval = 86400  # Check once per day (in seconds)

# Display sleep management
$savedDisplayTimeout = $null
$displaySleepManaged = $false

# Lid close action management
$savedLidCloseAction = $null
$lidCloseManaged = $false

# User preferences (loaded from config)
$userDisplayTimeoutMinutes = $null
$userLidCloseAction = $null

# Power plan management
$savedPowerPlan = $null
$powerPlanManaged = $false
$eGPUPowerPlanGuid = $null
# =========================

# Save runtime state for crash recovery
function Save-RuntimeState {
    param(
        [int]$DisplayTimeout,
        [int]$LidCloseAction,
        [string]$PowerPlan
    )
    
    try {
        $state = @{}
        
        # Load existing state if it exists
        if (Test-Path $runtimeStatePath) {
            $state = Get-Content $runtimeStatePath | ConvertFrom-Json -AsHashtable
        }
        
        # Update with new values
        if ($PSBoundParameters.ContainsKey('DisplayTimeout')) {
            $state.SavedDisplayTimeout = $DisplayTimeout
        }
        if ($PSBoundParameters.ContainsKey('LidCloseAction')) {
            $state.SavedLidCloseAction = $LidCloseAction
        }
        if ($PSBoundParameters.ContainsKey('PowerPlan')) {
            $state.SavedPowerPlan = $PowerPlan
        }
        
        $state | ConvertTo-Json | Set-Content $runtimeStatePath -ErrorAction SilentlyContinue
    } catch {
        # Silently fail - not critical
    }
}

# Clear runtime state items
function Clear-RuntimeState {
    param(
        [switch]$DisplayTimeout,
        [switch]$LidCloseAction,
        [switch]$PowerPlan,
        [switch]$All
    )
    
    try {
        if ($All -or -not (Test-Path $runtimeStatePath)) {
            Remove-Item $runtimeStatePath -ErrorAction SilentlyContinue
            return
        }
        
        $state = Get-Content $runtimeStatePath | ConvertFrom-Json -AsHashtable
        
        if ($DisplayTimeout) { $state.Remove('SavedDisplayTimeout') }
        if ($LidCloseAction) { $state.Remove('SavedLidCloseAction') }
        if ($PowerPlan) { $state.Remove('SavedPowerPlan') }
        
        if ($state.Count -eq 0) {
            Remove-Item $runtimeStatePath -ErrorAction SilentlyContinue
        } else {
            $state | ConvertTo-Json | Set-Content $runtimeStatePath -ErrorAction SilentlyContinue
        }
    } catch {
        # Silently fail - not critical
    }
}

# Restore settings on startup if script exited unexpectedly
function Restore-PreviousState {
    param([string]$currentEGPUState)
    
    if (-not (Test-Path $runtimeStatePath)) {
        return
    }
    
    try {
        $state = Get-Content $runtimeStatePath | ConvertFrom-Json
        $restored = $false
        
        # Only restore if eGPU is not currently present-ok
        # If eGPU is connected and working, we're in normal operation - clear state and continue
        if ($currentEGPUState -eq "present-ok") {
            Write-Log "eGPU connected on startup, clearing stale runtime state" "INFO"
            Clear-RuntimeState -All
            return
        }
        
        # eGPU is absent or disabled - restore saved settings from crash/reboot
        Write-Log "Detected runtime state from previous session, restoring settings..." "INFO"
        
        # Restore display timeout
        if ($state.PSObject.Properties.Name -contains 'SavedDisplayTimeout') {
            $timeoutMinutes = if ($null -ne $script:userDisplayTimeoutMinutes) {
                $script:userDisplayTimeoutMinutes
            } else {
                [math]::Ceiling($state.SavedDisplayTimeout / 60)
            }
            
            powercfg /change monitor-timeout-ac $timeoutMinutes | Out-Null
            Write-Log "Restored display timeout: $timeoutMinutes minutes" "INFO"
            $restored = $true
        }
        
        # Restore lid close action
        if ($state.PSObject.Properties.Name -contains 'SavedLidCloseAction') {
            try {
                $powerNamespace = @{ Namespace = 'root\cimv2\power' }
                $curPlan = Get-CimInstance @powerNamespace -Class Win32_PowerPlan -Filter "IsActive = TRUE"
                $lidSetting = Get-CimInstance @powerNamespace -ClassName Win32_Powersetting -Filter "ElementName = 'Lid close action'"
                
                if ($curPlan -and $lidSetting) {
                    $planGuid = [Regex]::Matches($curPlan.InstanceId, "{.*}").Value
                    $lidGuid = [Regex]::Matches($lidSetting.InstanceID, "{.*}").Value
                    
                    $pluggedInLidSetting = Get-CimInstance @powerNamespace -ClassName Win32_PowerSettingDataIndex `
                        -Filter "InstanceID = 'Microsoft:PowerSettingDataIndex\\$planGuid\\AC\\$lidGuid'"
                    
                    if ($pluggedInLidSetting) {
                        # Use user preference if set, otherwise use saved value
                        $restoreValue = if ($null -ne $script:userLidCloseAction) {
                            $script:userLidCloseAction
                        } else {
                            $state.SavedLidCloseAction
                        }
                        
                        $pluggedInLidSetting | Set-CimInstance -Property @{ SettingIndexValue = $restoreValue }
                        $curPlan | Invoke-CimMethod -MethodName Activate | Out-Null
                        
                        $actionName = switch ($restoreValue) { 0 {"Do Nothing"} 1 {"Sleep"} 2 {"Hibernate"} 3 {"Shut Down"} default {"Unknown"} }
                        Write-Log "Restored lid close action: $actionName" "INFO"
                        $restored = $true
                    }
                }
            } catch {
                Write-Log "Could not restore lid close action: $_" "WARNING"
            }
        }
        
        # Restore power plan
        if ($state.PSObject.Properties.Name -contains 'SavedPowerPlan') {
            powercfg -SETACTIVE $state.SavedPowerPlan | Out-Null
            Write-Log "Restored power plan from previous session" "INFO"
            $restored = $true
        }
        
        if ($restored) {
            Write-Log "Recovery: Settings restored after unexpected exit/reboot" "SUCCESS"
            Show-Notification -Title "eGPU Manager Started" -Message "Power settings restored to normal (eGPU not connected)"
        }
        
        # Clear runtime state after successful restore
        Clear-RuntimeState -All
    } catch {
        Write-Log "Could not restore previous state: $_" "WARNING"
    }
}

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
            # If already managing, do nothing
            if ($script:displaySleepManaged) {
                Write-Log "Set-DisplaySleep: Already managing display sleep, skipping disable." "INFO"
                return $true
            }

            # Read raw line with Current AC Power Setting Index
            $rawLine = powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE |
                       Select-String "Current AC Power Setting Index" -SimpleMatch |
                       ForEach-Object { $_.Line.Trim() } | Select-Object -First 1

            if (-not $rawLine) {
                Write-Log "Set-DisplaySleep: Could not read current AC timeout from powercfg." "WARNING"
                return $false
            }

            # Extract hex value (e.g. 0x00000078)
            if ($rawLine -match "0x[0-9A-Fa-f]+") {
                $hex = $Matches[0]
            } else {
                # If line contains ":" parted value like "Current AC Power Setting Index: 0x00000078"
                $parts = $rawLine -split ":" 
                $maybe = $parts[-1].Trim()
                if ($maybe -match "0x[0-9A-Fa-f]+") {
                    $hex = $Matches[0]
                } else {
                    Write-Log "Set-DisplaySleep: Failed to parse hex timeout from: '$rawLine'." "WARNING"
                    return $false
                }
            }

            # Convert hex string to integer seconds
            try {
                $seconds = [Convert]::ToInt32($hex, 16)
            } catch {
                Write-Log "Set-DisplaySleep: Failed to convert hex '$hex' to integer: $_" "WARNING"
                return $false
            }

            # Save seconds in script scope for restore
            $script:savedDisplayTimeout = $seconds
            
            # Persist to config file for crash recovery
            Save-RuntimeState -DisplayTimeout $seconds

            if ($seconds -ne 0) {
                powercfg /change monitor-timeout-ac 0 | Out-Null
                $script:displaySleepManaged = $true
                Write-Log "Display sleep disabled (saved timeout: $seconds seconds)" "INFO"
                return $true
            } else {
                Write-Log "Set-DisplaySleep: AC timeout already set to 'never' (0 seconds). Not changing." "INFO"
                return $false
            }
        } else {
            # Restore setting based on user preference or saved value
            if ($script:displaySleepManaged) {
                # Use user preference if set, otherwise use saved value
                if ($null -ne $script:userDisplayTimeoutMinutes) {
                    $timeoutMinutes = $script:userDisplayTimeoutMinutes
                    Write-Log "Restoring display sleep to user preference: $timeoutMinutes minutes" "INFO"
                } elseif ($null -ne $script:savedDisplayTimeout) {
                    $timeoutMinutes = [math]::Ceiling($script:savedDisplayTimeout / 60)
                    if ($script:savedDisplayTimeout -eq 0) {
                        $timeoutMinutes = 0
                    }
                    Write-Log "Restoring display sleep to saved value: $timeoutMinutes minutes (original: $($script:savedDisplayTimeout) seconds)" "INFO"
                } else {
                    Write-Log "Set-DisplaySleep: Nothing to restore (no saved or user preference value)." "INFO"
                    return $false
                }

                powercfg /change monitor-timeout-ac $timeoutMinutes | Out-Null
                $script:displaySleepManaged = $false
                
                # Clear from runtime state
                Clear-RuntimeState -DisplayTimeout
                
                return $true
            } else {
                Write-Log "Set-DisplaySleep: Nothing to restore (not previously managed or no saved value)." "INFO"
                return $false
            }
        }
    } catch {
        Write-Log "Failed to manage display sleep: $_" "WARNING"
        return $false
    }
}

# Manage power plan switching
function Set-PowerPlan {
    param(
        [bool]$UseEGPUPlan
    )

    try {
        if ($UseEGPUPlan) {
            # If already managing, do nothing
            if ($script:powerPlanManaged) {
                return $true
            }

            # Check if eGPU power plan exists
            if ($null -eq $script:eGPUPowerPlanGuid) {
                Write-Log "eGPU power plan not configured, skipping power plan switch" "INFO"
                return $false
            }

            # Get current active power plan
            try {
                $currentPlan = powercfg -GETACTIVESCHEME
                if ($currentPlan -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
                    $script:savedPowerPlan = $Matches[1]
                    
                    # Persist to config file for crash recovery
                    Save-RuntimeState -PowerPlan $script:savedPowerPlan
                    
                    # Don't switch if already on eGPU plan
                    if ($script:savedPowerPlan -eq $script:eGPUPowerPlanGuid) {
                        Write-Log "Already using eGPU power plan" "INFO"
                        return $false
                    }
                }
            } catch {
                Write-Log "Could not detect current power plan: $_" "WARNING"
                return $false
            }

            # Switch to eGPU power plan
            powercfg -SETACTIVE $script:eGPUPowerPlanGuid | Out-Null
            $script:powerPlanManaged = $true
            Write-Log "Switched to eGPU High Performance power plan" "SUCCESS"
            return $true
        } else {
            # Restore original power plan
            if ($script:powerPlanManaged -and $null -ne $script:savedPowerPlan) {
                powercfg -SETACTIVE $script:savedPowerPlan | Out-Null
                Write-Log "Restored original power plan" "INFO"
                $script:powerPlanManaged = $false
                
                # Clear from runtime state
                Clear-RuntimeState -PowerPlan
                
                return $true
            }
            return $false
        }
    } catch {
        Write-Log "Failed to manage power plan: $_" "WARNING"
        return $false
    }
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

# Manage lid close action
function Set-LidCloseAction {
    param(
        [bool]$DisableSleep
    )
    
    # Source: https://superuser.com/a/1700937 by KyleMit (CC BY-SA 4.0)
    
    try {
        $powerNamespace = @{ Namespace = 'root\cimv2\power' }
        
        if ($DisableSleep) {
            # If already managing, do nothing
            if ($script:lidCloseManaged) {
                return $true
            }

            # Get active plan and lid setting
            $curPlan = Get-CimInstance @powerNamespace -Class Win32_PowerPlan -Filter "IsActive = TRUE"
            $lidSetting = Get-CimInstance @powerNamespace -ClassName Win32_Powersetting -Filter "ElementName = 'Lid close action'"
            
            if (-not $curPlan -or -not $lidSetting) {
                Write-Log "Lid close action setting not available on this device" "INFO"
                return $false
            }
            
            # Get GUIDs
            $planGuid = [Regex]::Matches($curPlan.InstanceId, "{.*}").Value
            $lidGuid = [Regex]::Matches($lidSetting.InstanceID, "{.*}").Value
            
            # Get plugged in (AC) lid setting
            $pluggedInLidSetting = Get-CimInstance @powerNamespace -ClassName Win32_PowerSettingDataIndex `
                -Filter "InstanceID = 'Microsoft:PowerSettingDataIndex\\$planGuid\\AC\\$lidGuid'"
            
            if (-not $pluggedInLidSetting) {
                Write-Log "Could not retrieve AC lid close setting" "WARNING"
                return $false
            }
            
            # Save current action
            $script:savedLidCloseAction = $pluggedInLidSetting.SettingIndexValue
            
            # Persist to config file for crash recovery
            Save-RuntimeState -LidCloseAction $script:savedLidCloseAction

            # Set to "Do Nothing" (0) if not already
            if ($script:savedLidCloseAction -ne 0) {
                $pluggedInLidSetting | Set-CimInstance -Property @{ SettingIndexValue = 0 }
                $curPlan | Invoke-CimMethod -MethodName Activate | Out-Null
                
                $script:lidCloseManaged = $true
                $actionName = switch ($script:savedLidCloseAction) { 0 {"Do Nothing"} 1 {"Sleep"} 2 {"Hibernate"} 3 {"Shut Down"} default {"Unknown"} }
                Write-Log "Lid close action set to 'Do Nothing' (saved: $actionName)" "INFO"
                return $true
            }
            return $false
        } else {
            # Restore original setting
            if ($script:lidCloseManaged -and $null -ne $script:savedLidCloseAction) {
                $curPlan = Get-CimInstance @powerNamespace -Class Win32_PowerPlan -Filter "IsActive = TRUE"
                $lidSetting = Get-CimInstance @powerNamespace -ClassName Win32_Powersetting -Filter "ElementName = 'Lid close action'"
                
                $planGuid = [Regex]::Matches($curPlan.InstanceId, "{.*}").Value
                $lidGuid = [Regex]::Matches($lidSetting.InstanceID, "{.*}").Value
                
                $pluggedInLidSetting = Get-CimInstance @powerNamespace -ClassName Win32_PowerSettingDataIndex `
                    -Filter "InstanceID = 'Microsoft:PowerSettingDataIndex\\$planGuid\\AC\\$lidGuid'"
                
                # Use user preference if set, otherwise use saved value
                $restoreValue = if ($null -ne $script:userLidCloseAction) {
                    $script:userLidCloseAction
                } else {
                    $script:savedLidCloseAction
                }
                
                $pluggedInLidSetting | Set-CimInstance -Property @{ SettingIndexValue = $restoreValue }
                $curPlan | Invoke-CimMethod -MethodName Activate | Out-Null
                
                $actionName = switch ($restoreValue) { 0 {"Do Nothing"} 1 {"Sleep"} 2 {"Hibernate"} 3 {"Shut Down"} default {"Unknown"} }
                $source = if ($null -ne $script:userLidCloseAction) { "user preference" } else { "saved value" }
                Write-Log "Lid close action restored to '$actionName' ($source)" "INFO"
                $script:lidCloseManaged = $false
                
                # Clear from runtime state
                Clear-RuntimeState -LidCloseAction
                
                return $true
            }
            return $false
        }
    } catch {
        Write-Log "Failed to manage lid close action: $_" "WARNING"
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
        # Try WinRT toast notification (Windows 10/11)
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $appId = 'Microsoft.Windows.Explorer'
        $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
        $escapedMessage = [System.Security.SecurityElement]::Escape($Message)

        $toastXml = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$escapedTitle</text>
            <text>$escapedMessage</text>
        </binding>
    </visual>
    <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@

        $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xml.LoadXml($toastXml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)

        Write-Log "Notification shown: $Title" "INFO"
        return
    } catch {
        # Silently fall through to tray notification
    }

    # Fallback: System tray balloon notification
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText = $Message
        $notify.Visible = $true
        
        # Register event to clean up after balloon is shown
        $cleanup = Register-ObjectEvent -InputObject $notify -EventName BalloonTipClosed -Action {
            try {
                $Event.MessageData.Visible = $false
                $Event.MessageData.Dispose()
            } catch {}
            Unregister-Event -SourceIdentifier $EventSubscriber.SourceIdentifier
            Remove-Job -Id $EventSubscriber.Action.Id -Force
        } -MessageData $notify
        
        # Also set a timeout cleanup in case event doesn't fire
        $timeout = Register-ObjectEvent -InputObject ([System.Timers.Timer]@{Interval=6000;AutoReset=$false;Enabled=$true}) -EventName Elapsed -Action {
            try {
                $Event.MessageData.Visible = $false
                $Event.MessageData.Dispose()
            } catch {}
            Unregister-Event -SourceIdentifier $EventSubscriber.SourceIdentifier
            Remove-Job -Id $EventSubscriber.Action.Id -Force
        } -MessageData $notify
        
        $notify.ShowBalloonTip(5000)

        Write-Log "Notification shown (tray): $Title" "INFO"
    } catch {
        Write-Log "Could not show notification: $_" "WARNING"
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
        $currentVersion = $SCRIPT_VERSION
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
                             -Message "Version $latestVersion is available (you have $currentVersion). Run the installer to update."
            
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
    
    # Load user preferences
    if ($config.PSObject.Properties.Name -contains 'DisplayTimeoutMinutes') {
        $script:userDisplayTimeoutMinutes = $config.DisplayTimeoutMinutes
        Write-Log "Loaded display timeout preference: $($script:userDisplayTimeoutMinutes) minutes" "INFO"
    }
    if ($config.PSObject.Properties.Name -contains 'LidCloseActionAC') {
        $script:userLidCloseAction = $config.LidCloseActionAC
        $actionName = switch ($script:userLidCloseAction) { 0 {"Do Nothing"} 1 {"Sleep"} 2 {"Hibernate"} 3 {"Shut Down"} }
        Write-Log "Loaded lid close action preference: $actionName" "INFO"
    }
    if ($config.PSObject.Properties.Name -contains 'eGPUPowerPlanGuid') {
        $script:eGPUPowerPlanGuid = $config.eGPUPowerPlanGuid
        Write-Log "Loaded eGPU power plan GUID: $($script:eGPUPowerPlanGuid)" "INFO"
    }
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
Write-Log "Version: $SCRIPT_VERSION" "INFO"

# Get initial state
$script:lastKnownState = Get-eGPUState -egpu_name $egpu_name

# Restore settings from previous session if needed (reboot/crash recovery)
Restore-PreviousState -currentEGPUState $script:lastKnownState

# Check for updates
Check-ForUpdate -config $config

# Report initial state
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

# Register cleanup on script exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    # This won't restore settings, just clean up the state file on normal exit
    # Restoration only happens on crash/unexpected exit
    $runtimeStatePath = Join-Path $env:USERPROFILE ".egpu-manager\runtime-state.json"
    Remove-Item $runtimeStatePath -ErrorAction SilentlyContinue
}

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
            Show-Notification -Title "eGPU Disconnected" -Message "Your $egpu_name has been unplugged."
            
            # Restore power plan when eGPU is unplugged
            if ($script:powerPlanManaged) {
                Write-Log "Restoring original power plan" "INFO"
                Set-PowerPlan -UseEGPUPlan $false
            }
            
            # Restore display sleep when eGPU is unplugged
            if ($script:displaySleepManaged) {
                Write-Log "Restoring display sleep settings" "INFO"
                Set-DisplaySleep -Disable $false
            }
            
            # Restore lid close action when eGPU is unplugged
            if ($script:lidCloseManaged) {
                Write-Log "Restoring lid close action" "INFO"
                Set-LidCloseAction -DisableSleep $false
            }
        }
        elseif ($script:lastKnownState -eq "absent" -and $currentState -match "present") {
            Write-Log "eGPU physically reconnected" "INFO"
            
            if ($currentState -eq "present-disabled") {
                if (Enable-eGPU -egpu_name $egpu_name) {
                    Write-Log "eGPU enabled successfully via auto-enable" "SUCCESS"
                    Show-Notification -Title "eGPU Enabled" -Message "Your $egpu_name has been automatically enabled and is ready to use."
                    
                    # Switch to eGPU high performance power plan
                    Set-PowerPlan -UseEGPUPlan $true
                    
                    # Check if external monitors are connected and manage display sleep
                    if (Test-ExternalMonitor) {
                        Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                        Set-DisplaySleep -Disable $true
                    }
                    
                    # Disable lid close sleep action when eGPU is connected
                    Set-LidCloseAction -DisableSleep $true
                    
                    $currentState = "present-ok"
                } else {
                    Write-Log "Failed to enable eGPU" "ERROR"
                    Show-Notification -Title "eGPU Enable Failed" -Message "Could not automatically enable $egpu_name. Please check Device Manager."
                }
            }
            elseif ($currentState -eq "present-ok") {
                Write-Log "eGPU reconnected and already enabled" "SUCCESS"
                
                # Switch to eGPU high performance power plan
                Set-PowerPlan -UseEGPUPlan $true
                
                # Check if external monitors are connected and manage display sleep
                if (Test-ExternalMonitor) {
                    Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                    Set-DisplaySleep -Disable $true
                }
                
                # Disable lid close sleep action when eGPU is connected
                Set-LidCloseAction -DisableSleep $true
            }
        }
        elseif ($script:lastKnownState -eq "present-ok" -and $currentState -eq "present-disabled") {
            Write-Log "eGPU disabled (safe-removed)" "WARNING"
            Show-Notification -Title "eGPU Safe-Removed" -Message "Your $egpu_name has been safely removed. Reconnect it to auto-enable."
            
            # Restore power plan when eGPU is safe-removed
            if ($script:powerPlanManaged) {
                Write-Log "Restoring original power plan" "INFO"
                Set-PowerPlan -UseEGPUPlan $false
            }
            
            # Restore display sleep when eGPU is safe-removed
            if ($script:displaySleepManaged) {
                Write-Log "Restoring display sleep settings" "INFO"
                Set-DisplaySleep -Disable $false
            }
            
            # Restore lid close action when eGPU is safe-removed
            if ($script:lidCloseManaged) {
                Write-Log "Restoring lid close action" "INFO"
                Set-LidCloseAction -DisableSleep $false
            }
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "present-ok") {
            Write-Log "eGPU enabled manually or by another process" "INFO"
        }
        elseif ($script:lastKnownState -eq "present-disabled" -and $currentState -eq "absent") {
            Write-Log "eGPU physically unplugged (from disabled state)" "WARNING"
            
            # Restore power plan when eGPU is unplugged
            if ($script:powerPlanManaged) {
                Write-Log "Restoring original power plan" "INFO"
                Set-PowerPlan -UseEGPUPlan $false
            }
            
            # Restore display sleep when eGPU is unplugged
            if ($script:displaySleepManaged) {
                Write-Log "Restoring display sleep settings" "INFO"
                Set-DisplaySleep -Disable $false
            }
            
            # Restore lid close action when eGPU is unplugged
            if ($script:lidCloseManaged) {
                Write-Log "Restoring lid close action" "INFO"
                Set-LidCloseAction -DisableSleep $false
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
                    
                    # Switch to eGPU high performance power plan
                    Set-PowerPlan -UseEGPUPlan $true
                    
                    # Check if external monitors are connected and manage display sleep
                    if (Test-ExternalMonitor) {
                        Write-Log "External monitor(s) detected, disabling display sleep" "INFO"
                        Set-DisplaySleep -Disable $true
                    }
                    
                    # Disable lid close sleep action when eGPU is connected
                    Set-LidCloseAction -DisableSleep $true
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