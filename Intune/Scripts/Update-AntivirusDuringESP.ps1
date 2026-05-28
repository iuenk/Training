#=============================================================================================================================
# Script Name:     Update-AntivirusDuringESP.ps1
# Description:     This script will update antivirus signatures during the ESP phase
#   
# Notes      :     This script ensures that the antivirus signatures are up-to-date during the ESP phase.
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

# Function to log messages in CMTrace format and write to host
Function Write-Log {
    param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyCollection()]
        [Alias('Text')]
        [String[]]$Message,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 3)]
        [Int16]$Severity = 1,
		[Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNull()]
        [String]$Source = $([String]$parentFunctionName = [IO.Path]::GetFileNameWithoutExtension((Get-Variable -Name 'MyInvocation' -Scope 1 -ErrorAction 'SilentlyContinue').Value.MyCommand.Name); If ($parentFunctionName) {
                $parentFunctionName
            }
            Else {
                'Unknown'
            }),
		[Parameter(Mandatory = $false, Position = 3)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileDirectory = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs",
		[Parameter(Mandatory = $false, Position = 4)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileName = "UpdateAntivirusduringESP.log"
    )
	[DateTime]$DateTimeNow = Get-Date
    [String]$LogTime = $DateTimeNow.ToString('HH\:mm\:ss.ffffff')
    [String]$LogDate = $DateTimeNow.ToString('MM-dd-yyyy')
	try {
        If ($script:MyInvocation.Value.ScriptName) {
            [String]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
        } Else {
            [String]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.signature -Leaf -ErrorAction 'Stop'
        }
    }
    catch {
        $ScriptSource = ''
    }
    $CMTraceMessage = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTime`" " + "date=`"$LogDate`" " + "component=`"$Source`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
	## Assemble the fully qualified path to the log file
    [String]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
    $CMTraceMessage | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
	Switch ($Severity) {
		3 {
			Write-Host -Object $Message -ForegroundColor 'Red'
        }
        2 {
			Write-Host -Object $Message -ForegroundColor 'Yellow'
        }
        1 {
			Write-Host -Object $Message
        }
    }
}

# Check if running during ESP phase
function Is-ESPPhase {
    try {
        $loggedOnUser = (Get-CimInstance -ClassName Win32_ComputerSystem).Username
        if (($loggedOnUser -like '*\defaultuser0') -and (((Get-Process -Name 'wwahost' -ErrorAction 'SilentlyContinue').count) -gt 0)) {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

# Start logging
Write-Log -Message "Starting antivirus signatures update."

if (Is-ESPPhase) {
    Write-Log -Message "Script is running during the ESP phase of Autopilot."
    try {
        # Get age of antivirus signatures and only update if the antivirus signatures are older then 1 day
        Write-Log -Message "Attempting to get antivirus signatures statistics."
        $MpStatus=Get-MpComputerStatus -ErrorAction Stop
    } catch {
        Write-Log -Message "Error getting antivirus signatures statistics: $_" -Severity 3
    }
    try {
        if ($MpStatus) {
            Write-Log -Message "Antivirus signatures statistics - Age:$($MpStatus.AntivirusSignatureAge) Version:$($MpStatus.AntivirusSignatureVersion) LastUpdated:$($MpStatus.AntivirusSignatureLastUpdated)"
            if ($($MpStatus.AntivirusSignatureAge) -gt 1) {
                # Update antivirus signatures
                Write-Log -Message "Attempting to update antivirus signatures."
                Update-MpSignature -UpdateSource MicrosoftUpdateServer -ErrorAction Stop
                Write-Log -Message "Antivirus signatures updated successfully."
            } else {
                Write-Log -Message "Antivirus signatures already up-to-date"
            }
        }
    } catch {
        Write-Log -Message "Error updating antivirus signatures: $_" -Severity 3
    }
} else {
    Write-Log -Message "Script is not running during the ESP phase of Autopilot. Exiting." -Severity 2
}

# End logging
Write-Log -Message "Antivirus signatures update process completed."