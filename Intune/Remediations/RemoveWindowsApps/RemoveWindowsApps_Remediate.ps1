#=============================================================================================================================
# Script Name:     RemoveWindowsApps_Remediate.ps1
# Description:     Script detect build-in Windows apps on Windows 10/11 that we want to remove. 
#   
# Notes      :     
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'RemoveWindowsApps_Remediate'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"

# will remove MicrosoftTeams, Xbox App, Xbox Gaming Overlay, Cortana, Getstarted and Quick Assist
$Packages = @(
	"MicrosoftTeams",
	"Microsoft.XboxApp",
	"Microsoft.XboxGamingOverlay",
	"Microsoft.549981C3F5F10",
	"Microsoft.Getstarted",
	"MicrosoftCorporationII.QuickAssist"
)

#### Define Write_Log function ####
Function Write_Log
{
param(
$Message_Type, 
$Message
)
    $MyDate = "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)  
    Add-Content $Log_File  "$MyDate - $Message_Type : $Message"  
} 

if(Test-Path -Path $Log_File){
    if((Get-Item -Path $Log_File).Length -gt '10000') {Remove-Item -Path $Log_File -Force}
}

$AppsRemoved = 0
$AppsNotRemoved = 0

foreach($App in $Apps){
    try{
        Get-AppxPackage -Name $App | Remove-AppxPackage -ErrorAction stop
        Write_Log -Message_Type "INFO" -Message "$App successfully removed"
        $AppsRemoved += 1
    }
    catch{
        Write_Log -Message_Type "ERROR" -Message "Error removing $App" -ForegroundColor Red
        $AppsNotRemoved += 1
    }
}

if($AppsRemoved -eq $Apps.count){
    Write_Log -Message_Type "INFO" -Message "Windows apps are successfully removed"
    $EC += 0
}
else{
    Write_Log -Message_Type "ERROR" -Message "Failed to remove $AppsNotRemoved Windows apps" -ForegroundColor Red
    $EC += 1
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode


try{
    Get-AppxPackage -Name MicrosoftTeams | Remove-AppxPackage
    Write_Log -Message_Type "INFO" -Message "Correct Microsoft Teams app successfully removed"
    $EC += 0
}
catch{
    Write_Log -Message_Type "ERROR" -Message "Error removing Microsoft Teams app" -ForegroundColor Red
	$EC += 1
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode