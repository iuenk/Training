#=============================================================================================================================
# Script Name:     UpdateHealthTools_Detect.ps1
# Description:     Check if Microsoft Update Health Tools is installed on the device
#   
# Notes      :     Check if Microsoft Update Health Tools is installed on the device
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Component / correlation context
$ComponentName = 'MS_Update_Health_Detection'
$CorrelationId = [System.Guid]::NewGuid().ToString()

function Write-WENCmwEvent {
<#
.SYNOPSIS
    Writes observable log information as verbose output or to the WEN_CMW event log.

.DESCRIPTION
    - Severity "Info"   → Write-Verbose (plain text, no JSON).
    - Severity "Warning" or "Error":
        • Write-Verbose (plain text)
        • Write structured JSON entry to WEN_CMW Windows Event Log.

.PARAMETER Message
    The log message to write.

.PARAMETER Severity
    Logging severity. Allowed: Info, Warning, Error.

.PARAMETER EventId
    Unique event ID (3200–3999) for event log classification.

.PARAMETER Source
    Event log source name. Defaults to the script-level $ComponentName.

.PARAMETER LogName
    Event log name. Defaults to 'WEN_CMW'.

.PARAMETER CorrelationId
    GUID used for correlating events across operations.

.PARAMETER FunctionName
    Logical function name for observability. Defaults to the current command name.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('Info','Warning','Error')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateRange(3200, 3999)]
        [int]$EventId,

        [Parameter()]
        [string]$Source = $ComponentName,

        [Parameter()]
        [string]$LogName = 'WEN_CMW',

        [Parameter()]
        [string]$CorrelationId,

        [Parameter()]
        [string]$FunctionName
    )

    try {
        $timestamp = (Get-Date).ToString('o')
        if (-not $FunctionName) {
            $FunctionName = $MyInvocation.MyCommand.Name
        }

        # Verbose output: plain text only
        $verboseMessage = "[{0}] {1}" -f $timestamp, $Message
        Write-Verbose $verboseMessage

        # Only Warning/Error go into event log
        if ($Severity -eq 'Info') {
            return
        }

        # JSON payload used only for event log
        $payload = [ordered]@{
            Timestamp     = $timestamp
            Severity      = $Severity
            EventId       = $EventId
            Source        = $Source
            Function      = $FunctionName
            CorrelationId = $CorrelationId
            Message       = $Message
        }

        $jsonMessage = $payload | ConvertTo-Json -Depth 5

        # Ensure the event source & log exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($Source)) {
            if (-not [System.Diagnostics.EventLog]::Exists($LogName)) {
                New-EventLog -LogName $LogName -Source $Source
            }
            else {
                New-EventLog -LogName $LogName -Source $Source
            }
        }

        $entryType = [System.Diagnostics.EventLogEntryType]::$Severity

        Microsoft.PowerShell.Management\Write-EventLog `
            -LogName  $LogName `
            -Source   $Source `
            -EntryType $entryType `
            -EventId  $EventId `
            -Message  $jsonMessage
    }
    catch {
        Write-Verbose ("Write-WENCmwEvent failed: {0}" -f $_.Exception.Message)
    }
}

function Test-MicrosoftUpdateHealthToolsInstalled {
<#
.SYNOPSIS
    Tests whether Microsoft Update Health Tools is installed.

.DESCRIPTION
    Searches the standard uninstall registry locations (32-bit and 64-bit) for
    a product with DisplayName equal to "Microsoft Update Health Tools".

.OUTPUTS
    [bool] True if installed, otherwise False.
#>
    [CmdletBinding()]
    param()

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $results = foreach ($key in $uninstallKeys) {
        if (Test-Path -Path $key) {
            Get-ChildItem -Path $key | ForEach-Object {
                try {
                    if ($_.GetValue('DisplayName') -eq 'Microsoft Update Health Tools') {
                        [PSCustomObject]@{
                            DisplayName    = $_.GetValue('DisplayName')
                            DisplayVersion = $_.GetValue('DisplayVersion')
                            InstallDate    = $_.GetValue('InstallDate')
                            GUID           = $_.PsChildName
                        }
                    }
                }
                catch {
                    Write-WENCmwEvent -Message ("Failed to inspect uninstall entry: {0}" -f $_.Exception.Message) `
                                      -Severity 'Warning' -EventId 3203 -CorrelationId $CorrelationId `
                                      -FunctionName 'Test-MicrosoftUpdateHealthToolsInstalled'
                }
            }
        }
        else {
            Write-WENCmwEvent -Message ("Uninstall registry path not found: {0}" -f $key) `
                              -Severity 'Warning' -EventId 3202 -CorrelationId $CorrelationId `
                              -FunctionName 'Test-MicrosoftUpdateHealthToolsInstalled'
        }
    }

    if ($results) {
        foreach ($result in $results) {
            $json = $result | ConvertTo-Json -Compress
            # Intune-friendly detection output
            Write-Host $json
            Write-WENCmwEvent -Message ("Detected Microsoft Update Health Tools: {0}" -f $json) `
                              -Severity 'Info' -EventId 3204 -CorrelationId $CorrelationId `
                              -FunctionName 'Test-MicrosoftUpdateHealthToolsInstalled'
        }
        return $true
    }

    return $false
}

try {
    Write-WENCmwEvent -Message 'Detection script started.' -Severity 'Info' -EventId 3200 `
                      -CorrelationId $CorrelationId -FunctionName 'Main'

    # Check minimum OS version requirement (Windows 10 1809 / build 17763 or later)
    [int]$currentBuild = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                                          -Name 'CurrentBuildNumber' |
                      Select-Object -ExpandProperty CurrentBuildNumber

    if ($currentBuild -lt 17763) {
        $msg = "Minimum OS version requirement not met. CurrentBuild=$currentBuild, Required>=17763."
        Write-Host 'Minimum OS version requirement not met'
        Write-WENCmwEvent -Message $msg -Severity 'Warning' -EventId 3201 `
                          -CorrelationId $CorrelationId -FunctionName 'Main'
        # Treat unsupported OS as compliant
        exit 0
    }

    if (Test-MicrosoftUpdateHealthToolsInstalled) {
        Write-Host 'Microsoft Update Health Tools is installed'
        Write-WENCmwEvent -Message 'Microsoft Update Health Tools is installed.' `
                          -Severity 'Info' -EventId 3204 -CorrelationId $CorrelationId `
                          -FunctionName 'Main'
        exit 0
    }
    else {
        Write-Host 'Microsoft Update Health Tools not found'
        Write-WENCmwEvent -Message 'Microsoft Update Health Tools not found.' `
                          -Severity 'Info' -EventId 3205 -CorrelationId $CorrelationId `
                          -FunctionName 'Main'
        exit 1
    }
}
catch {
    $errorMessage = "Detection script failed: $($_.Exception.Message)"
    $detail = "$errorMessage`nStackTrace:`n$($_.ScriptStackTrace)"
    Write-Host $errorMessage
    Write-WENCmwEvent -Message $detail -Severity 'Error' -EventId 3206 `
                      -CorrelationId $CorrelationId -FunctionName 'Main'
    exit 1
}