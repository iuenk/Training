#=============================================================================================================================
# Script Name:     ManageEventLogs_Remediate.ps1
# Description:     Remediate script of Proactive Remediation script to manage EventLogs.
#
# Notes      :     Script to Enable/Disable specific EventLogs; and manage their settings.
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$ErrorActionPreference = 'Stop'
$EventLogs = @(
    [PSCustomObject]@{
        LogName             = "Microsoft-Windows-TaskScheduler/Operational"
        LogPath             = "%SystemRoot%\System32\Winevt\Logs\Microsoft-Windows-TaskScheduler%4Operational.evtx"  
        Enabled             = $true
        MaximumSizeInBytes  = 10485760
        LogMode             = "Circular"
        IsClassicLog        = $false
    }
    [PSCustomObject]@{
        LogName             = "UCORP_CMW"
        LogPath             = "%SystemRoot%\System32\Winevt\Logs\UCORP_CMW.evtx"
        Enabled             = $true
        MaximumSizeInBytes  = 8388608
        LogMode             = "Circular"
        IsClassicLog        = $true
    }
    <#
    [PSCustomObject]@{
        LogName             = "TestLog2"
        LogPath             = "%SystemRoot%\System32\Winevt\Logs\TestLog2.evtx"
        Enabled             = $true
        MaximumSizeInBytes  = 20971520
        LogMode             = "Circular"
        IsClassicLog        = $true
    }
    #>
    # Add more log objects as needed
)

$resultString = ""

foreach ($log in $EventLogs) {
    $logName = $log.LogName
    $logSettings = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue

    if ($null -eq $logSettings) {
        If ($log.IsClassicLog) {
            # Create classic event log
            New-EventLog -LogName $logName -Source "ING" -ErrorAction SilentlyContinue
            Limit-EventLog -LogName $logName -MaximumSize $log.MaximumSizeInBytes
            Write-EventLog -LogName $logName -Source "ING" -EntryType Information -Message "Initial Event Log Created" -EventId 1
            $resultString += "'$logName' created."
        } else {
            # modern event log creation requires more work. Not supported in this script
            $resultString += " '$logName' does not exist and is not a classic log. Manual creation required."
        }
    } else {
        # Log exists, check settings
        $settingChange = $false
        $isEnabled = $logSettings.IsEnabled
        $logPath = $logSettings.LogFilePath
        $maxSize = $logSettings.MaximumSizeInBytes
        $logMode = $logSettings.LogMode.ToString()

        if ($isEnabled -ne $log.Enabled) {
            $logSettings.IsEnabled = $log.Enabled
            $resultString += " '$logName' set Enabled."
            $settingChange = $true
        }
        if ($logPath -ne $log.LogPath) {
            $logSettings.LogFilePath = $log.LogPath
            $resultString += " '$logName' path changed to $($log.LogPath)."
            $settingChange = $true
        }
        if ($maxSize -ne $log.MaximumSizeInBytes) {
            $logSettings.MaximumSizeInBytes = $log.MaximumSizeInBytes
            $resultString += " '$logName' max size changed to $($log.MaximumSizeInBytes)."
            $settingChange = $true
        }
        if ($logMode -ne $log.LogMode) {
            $logSettings.LogMode = $log.LogMode
            $resultString += " '$logName' log mode changed to $($log.LogMode)."
            $settingChange = $true
        }
        If ($settingChange) {
            # Apply changes
            $logSettings.SaveChanges()
        }
    }
}

# If PR tries to create modern log; exit 1, as it is not built to do so
If ($resultString -match 'does not exist and is not a classic log. Manual creation required.') {
    $resultString += ' Exit 1.'
    Write-Host $resultString
    exit 1
} else {
    $resultString += ' Exit 0.'
    Write-Host $resultString
    exit 0
}