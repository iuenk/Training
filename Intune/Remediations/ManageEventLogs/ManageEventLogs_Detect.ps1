#=============================================================================================================================
# Script Name:     ManageEventLogs_Detect.ps1
# Description:     Detect script of Proactive Remediation script to manage EventLogs.
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
        $resultString += "Log '$logName' does not exist."
    } else {
        # Log exists, check settings
        $isEnabled = $logSettings.IsEnabled
        $logPath = $logSettings.LogFilePath
        $maxSize = $logSettings.MaximumSizeInBytes
        $logMode = $logSettings.LogMode.ToString()

        if ($isEnabled -ne $log.Enabled) {
            $resultString += " '$logName' disabled."
        }
        if ($logPath -ne $log.LogPath) {
            $resultString += " '$logName' path mismatch."
        }
        if ($maxSize -ne $log.MaximumSizeInBytes) {
            $resultString += " '$logName' max size mismatch."
        }
        if ($logMode -ne $log.LogMode) {
            $resultString += " '$logName' log mode mismatch."
        }
    }
}

If ($resultString -eq "") {
    Write-Host "All specified Event Logs are configured correctly."
    Exit 0
} else {
    Write-Host $resultString
    Exit 1
}