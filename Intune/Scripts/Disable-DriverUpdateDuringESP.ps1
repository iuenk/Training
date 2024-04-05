#=============================================================================================================================
# Script Name:    Disable-DriverUpdateduringESP.ps1
# Description:    This script will disable the Windows Update Driver update
#   
# Notes      :     Version 1.0: Initial version as advise by MS Case 28927447 / Karan Rustagi      
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$logfilepath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DisableDriverUpdateduringESP.log"

function WriteToLogFile ($message)
{
   #$timestamp = [DateTime]::UtcNow.ToString('r')
   # we need to get the time via command box, because powershell Get-Date will convert it back in relation to time zone.
   $timestamp = cmd /c echo  %date%-%time% '2>&1'

   $message = "[" + $timestamp + "] " + $message 
   Add-content $logfilepath -value $message
}

$Regpath = "HKLM:\Software\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup"

$Regkey = "HasProvisioningCompleted"



If (Get-Process -Name 'CloudExperienceHostBroker' -ErrorAction SilentlyContinue) {$CloudExpBroker = $true }

If (((Get-Item $regpath -EA Ignore).Property -contains $regkey) -eq $false) {$regcheck = $true}



If (($CloudExpBroker -eq $true) -and ($regcheck -eq $true)) {

    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching\' -Name "SearchOrderConfig" -Value 3
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata\' -Name "PreventDeviceMetadataFromNetwork" -Value 1
    
    If ((Test-Path -Path 'HKLM:\SOFTWARE\policies\Microsoft\Windows\WindowsUpdate') -eq $false){New-Item -Path 'HKLM:\policies\SOFTWARE\Microsoft\Windows\WindowsUpdate'}
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\policies\Microsoft\Windows\WindowsUpdate' -Name "ExcludeWUDriversInQualityUpdate" -Value 1
    
    Restart-Service -Name wuauserv

    $ServState = Get-Service wuauserv
    $ServState.WaitForStatus("Running",'00:00:10')

    $ServState = Get-Service wuauserv
    If ($ServState.status -eq "Running"){
        WriteToLogFile "Registry values set and service restarted"
        #Exit 0
    }else{
        WriteToLogFile "Registry values set and service no restarted"
        #Exit 1
    }

} else {

    WriteToLogFile "device is NOT in ESP"
    #Exit 0

}

