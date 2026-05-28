#=============================================================================================================================
# Script Name:     Set-WingetUpdate.ps1
# Description:     This script will create a scheduled task that will run winget upgrade --all on startup
#   
# Notes      :     Update all packages that are installed or can be configured by using Winget
#                  Only tested in Windows 10
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$TaskPath = 'C:\Windows\system32\Tasks'
$TaskFolder = 'Ucorp'
$TaskName = 'WingetUpdate'
$RegCheck = 'WingetUpdate'
$version = 1
$RegRoot= "HKLM"

if(Test-Path HKLM:\Software\Ucorp){
    $regexist = Get-ItemProperty "$RegRoot`:\Software\Ucorp" -Name $RegCheck -ErrorAction SilentlyContinue
}
else{
    if(!(Test-Path "$RegRoot`:\Software\Ucorp")){
        New-Item HKLM:\Software\Ucorp
    }
}    
if((!($regexist)) -or ($regexist.$RegCheck -lt $Version)){
    try{
        # Will remove previous scheduled task set so it can be redeployed
        if(Test-Path $TaskPath){
            $RemoveTrigger = "schtasks /Delete /TN '$TaskFolder\$TaskName' /F"
            Invoke-Expression $RemoveTrigger
        }
        try{
            $A = New-ScheduledTaskAction -Execute "Powershell" -Argument "-command & {winget upgrade --all}"
            $T = New-ScheduledTaskTrigger -AtStartup
            $P = New-ScheduledTaskPrincipal -UserId 'system'
            $S = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
            $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
            Register-ScheduledTask  -TaskName "$TaskFolder\$TaskName" -InputObject $D -ErrorAction Stop

            # Only set registry when action succeeded
            if($regexist.$RegCheck){
                set-ItemProperty HKLM:\Software\Ucorp -Name $RegCheck -Value $version -ErrorAction Stop -Force
            }
            else{
                new-ItemProperty HKLM:\Software\Ucorp -Name $RegCheck -Value $version -PropertyType string -ErrorAction Stop -Force
            }
        }
        catch{
            write-error 'failed to create scheduledtask'
            break
        }
    }
    catch{
        write-error 'failed to schedule weekly winget update apps'
        break
    }
}