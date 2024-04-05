#=============================================================================================================================
# Script Name:     RemoveWindowsApps_Detect.ps1
# Description:     Script detect build-in Windows apps on Windows 10/11 that we want to remove. 
#   
# Notes      :     
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'RemoveWindowsApps_Detect'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"

# Will remove MicrosoftTeams, Xbox App, Xbox Gaming Overlay, Cortana, Getstarted and Quick Assist
$Apps = @(
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

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName DETECT ############################"

$AppsFound = 0
$AppsNotFound = 0

foreach($App in $Apps){
    if(!(Get-AppxPackage -Name $App)){
        $AppsNotFound += 1        
    }
    else{
        Write_Log -Message_Type "ERROR" -Message "$App found" -ForegroundColor Red
        $AppsFound += 1
    }
}

if($AppsNotFound -eq $Apps.count){
    Write_Log -Message_Type "INFO" -Message "Windows apps not found"
    $EC += 0
}
else{
    Write_Log -Message_Type "ERROR" -Message "$AppsFound Windows apps found" -ForegroundColor Red
    $EC += 1
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode