#=============================================================================================================================
# Script Name:    Disable-DriverUpdateduringESP.ps1
# Description:    This script will disable the Windows Update Driver update
#   
# Notes      :     Version 1.0: Initial version as advise by MS Case 28927447 / Karan Rustagi      
#
# Created by :     Ivo Uenk
# Date       :     15-5-2026
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

if (Get-Process -Name 'CloudExperienceHostBroker' -ErrorAction SilentlyContinue){$CloudExpBroker = $true}
if (((Get-Item $regpath -EA Ignore).Property -contains $regkey) -eq $false){$regcheck = $true}

if (($CloudExpBroker -eq $true) -and ($regcheck -eq $true)){
    WriteToLogFile "Device is in device enrollment"

    $WUService = Get-Service -Name wuauserv| Select-Object Status, StartType
    WriteToLogFile $WUService

    Stop-service -Name wuauserv -Force 
    Set-Service -Name wuauserv -Status stopped -StartupType disabled

    Start-Sleep -Seconds 10

    $WUService = Get-Service -Name wuauserv| Select-Object Status, StartType
    
    if ($WUService.StartType -eq "Disabled"){
        WriteToLogFile $WUService
        WriteToLogFile "Windows Update Service Disabled"
        Exit 0
    } 
    else {  
        WriteToLogFile $WUService
        WriteToLogFile "Windows Update Service not disabled"
        Exit 1
    }
} 
else {
    WriteToLogFile "Device is NOT in ESP"
    $WUService = Get-Service -Name wuauserv| Select-Object Status, StartType
    WriteToLogFile $WUService

    Set-Service -Name wuauserv -status Running -StartupType manual
    Start-Sleep -Seconds 10

    $WUService = Get-Service -Name wuauserv| Select-Object Status, StartType
    
    if ($WUService.StartType -eq "Manual"){
        WriteToLogFile $WUService
        WriteToLogFile "Windows Update Service set to manual"
        exit 0
    } 
    else {  
        WriteToLogFile $WUService
        WriteToLogFile "Windows Update Service has an unknown state"
        exit 1
    }
    exit 0
}
