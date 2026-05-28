#=============================================================================================================================
# Script Name:     UpdateHealthTools_Remediate.ps1
# Description:     Remediate Microsoft Update Health Tools installation on the device
#   
# Notes      :     Check if Microsoft Update Health Tools is installed on the device
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'

# Component / correlation context
$ComponentName = 'MS_Update_Health_Remediation'
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

        # Ensure event source & log exist
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

function Get-UpdateHealthToolsMsiPath {
<#
.SYNOPSIS
    Resolves the correct UpdHealthTools.msi path based on OS version.

.DESCRIPTION
    Uses the OS build to determine:
        - Windows 10            → "Windows 10\UpdHealthTools.msi"
        - Windows 11 21H2       → "Windows 11 21H2\UpdHealthTools.msi"
        - Windows 11 22H2 and + → "Windows 11 22H2+\UpdHealthTools.msi"

    Assumes that the root folder of the extracted ZIP is "Expedite_packages"
    under the specified base directory.

.PARAMETER BaseDirectory
    The directory where "Expedite_packages" exists.

.OUTPUTS
    [System.IO.FileInfo] for the MSI file, or $null if not found.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseDirectory
    )

    [int]$currentBuild = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
                                          -Name 'CurrentBuildNumber' |
                      Select-Object -ExpandProperty CurrentBuildNumber

    if ($currentBuild -lt 22000) {
        $subFolder = 'Windows 10'
    }
    elseif ($currentBuild -lt 22621) {
        $subFolder = 'Windows 11 21H2'
    }
    else {
        $subFolder = 'Windows 11 22H2+'
    }

    $expediteRoot = Join-Path -Path $BaseDirectory -ChildPath 'Expedite_packages'
    $targetFolder = Join-Path -Path $expediteRoot -ChildPath $subFolder

    Write-WENCmwEvent -Message ("OS build: {0}, subFolder: {1}, targetFolder: {2}" -f $currentBuild, $subFolder, $targetFolder) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Get-UpdateHealthToolsMsiPath'

    if (-not (Test-Path -Path $targetFolder)) {
        Write-WENCmwEvent -Message ("Target folder not found: {0}" -f $targetFolder) `
                          -Severity 'Error' -EventId 3213 -CorrelationId $CorrelationId `
                          -FunctionName 'Get-UpdateHealthToolsMsiPath'
        return $null
    }

    $msi = Get-ChildItem -Path $targetFolder -Filter 'UpdHealthTools.msi' -File -ErrorAction SilentlyContinue |
           Select-Object -First 1

    if (-not $msi) {
        Write-WENCmwEvent -Message ("UpdHealthTools.msi not found in {0}" -f $targetFolder) `
                          -Severity 'Error' -EventId 3214 -CorrelationId $CorrelationId `
                          -FunctionName 'Get-UpdateHealthToolsMsiPath'
        return $null
    }

    Write-WENCmwEvent -Message ("Resolved MSI path: {0}" -f $msi.FullName) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Get-UpdateHealthToolsMsiPath'

    return $msi
}

function Invoke-MicrosoftUpdateHealthToolsRemediation {
<#
.SYNOPSIS
    Downloads and installs Microsoft Update Health Tools.

.DESCRIPTION
    - Downloads the Expedite_packages.zip from Microsoft.
    - Extracts the package to a temp folder.
    - Determines the appropriate MSI based on OS version (Win10 / Win11 21H2 / Win11 22H2+).
    - Installs the MSI silently via msiexec.
    - Writes warnings/errors to WEN_CMW event log; all other traces as verbose.

.OUTPUTS
    [int] Exit code returned by msiexec (0 = success).
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $downloadDirectory  = $env:TEMP
    $downloadFileName   = 'Expedite_packages.zip'
    $logDirectory       = $env:TEMP
    $msiLogFile         = 'UpdateTools_MSI.log'
    $ProgressPreference = 'SilentlyContinue'
    $url                = 'https://www.microsoft.com/en-us/download/details.aspx?id=103324'

    Write-WENCmwEvent -Message ("Remediation started. DownloadDirectory={0}" -f $downloadDirectory) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    # 1. Get the download URL
    Write-WENCmwEvent -Message ("Requesting download page: {0}" -f $url) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    $request = Invoke-WebRequest -Uri $url -UseBasicParsing

    $downloadUrl = ($request.Links | Where-Object { $_.outerHTML -match 'Download button' }).href
    if (-not $downloadUrl) {
        $msg = 'Failed to determine download URL from Microsoft page.'
        Write-WENCmwEvent -Message $msg -Severity 'Error' -EventId 3211 -CorrelationId $CorrelationId `
                          -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'
        return 1
    }

    Write-WENCmwEvent -Message ("Resolved download URL: {0}" -f $downloadUrl) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    # 2. Download and extract the ZIP package
    $zipPath = Join-Path -Path $downloadDirectory -ChildPath $downloadFileName

    Write-WENCmwEvent -Message ("Downloading ZIP to {0}" -f $zipPath) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    if (-not (Test-Path -Path $zipPath)) {
        $msg = 'Update tools ZIP not downloaded.'
        Write-Host $msg
        Write-WENCmwEvent -Message $msg -Severity 'Error' -EventId 3212 -CorrelationId $CorrelationId `
                          -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'
        return 1
    }

    Write-WENCmwEvent -Message ("Expanding archive {0} to {1}" -f $zipPath, $downloadDirectory) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    Expand-Archive -Path $zipPath -DestinationPath $downloadDirectory -Force

    # 3. Resolve the correct MSI based on OS
    $msiFile = Get-UpdateHealthToolsMsiPath -BaseDirectory $downloadDirectory
    if (-not $msiFile) {
        $msg = 'Unable to resolve the correct UpdHealthTools.msi for this OS.'
        Write-Host $msg
        Write-WENCmwEvent -Message $msg -Severity 'Error' -EventId 3215 -CorrelationId $CorrelationId `
                          -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'
        return 1
    }

    # 4. Install the MSI
    if (-not (Test-Path -Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $msiLogPath = Join-Path -Path $logDirectory -ChildPath $msiLogFile
    $arguments  = "/i `"$($msiFile.FullName)`" /qn REBOOT=ReallySuppress /L*V `"$msiLogPath`""

    Write-WENCmwEvent -Message ("Starting msiexec with arguments: {0}" -f $arguments) `
                      -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                      -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

    if ($PSCmdlet.ShouldProcess($msiFile.FullName, 'Install Microsoft Update Health Tools')) {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru

        Write-WENCmwEvent -Message ("msiexec exit code: {0}. MSI log: {1}" -f $process.ExitCode, $msiLogPath) `
                          -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                          -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'

        return $process.ExitCode
    }
    else {
        Write-WENCmwEvent -Message 'Installation skipped due to ShouldProcess / -WhatIf.' `
                          -Severity 'Warning' -EventId 3216 -CorrelationId $CorrelationId `
                          -FunctionName 'Invoke-MicrosoftUpdateHealthToolsRemediation'
        return 1
    }
}

try {
    $exitCode = Invoke-MicrosoftUpdateHealthToolsRemediation

    if ($exitCode -eq 0) {
        $msg = 'Microsoft Update Health Tools successfully installed.'
        Write-Host $msg
        Write-WENCmwEvent -Message $msg -Severity 'Info' -EventId 3210 -CorrelationId $CorrelationId `
                          -FunctionName 'Main'
        exit 0
    }
    else {
        $msg = "Microsoft Update Health Tools installation failed with exit code $exitCode."
        Write-Host $msg
        Write-WENCmwEvent -Message $msg -Severity 'Error' -EventId 3216 -CorrelationId $CorrelationId `
                          -FunctionName 'Main'
        exit 1
    }
}
catch {
    $errorMessage = "Remediation script failed: $($_.Exception.Message)"
    $detail = "$errorMessage`nStackTrace:`n$($_.ScriptStackTrace)"
    Write-Host $errorMessage
    Write-WENCmwEvent -Message $detail -Severity 'Error' -EventId 3217 `
                      -CorrelationId $CorrelationId -FunctionName 'Main'
    exit 1
}