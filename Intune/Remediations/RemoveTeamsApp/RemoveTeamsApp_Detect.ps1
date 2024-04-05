#=============================================================================================================================
# Script Name:     RemoveTeamsApp_Detect.ps1
# Description:     Script detect the new Microsoft Teams consumer app on Windows 11
#   
# Notes      :     App must be removed because this app can only be used with personal Microsoft accounts
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'RemoveTeamsApp_Detect'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"

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

if($null -eq (Get-AppxPackage -Name MicrosoftTeams)){
    Write_Log -Message_Type "INFO" -Message "Correct Microsoft Teams client not found"
	$EC += 0
}
else{
    Write_Log -Message_Type "ERROR" -Message "Microsoft Teams client found" -ForegroundColor Red
	$EC += 1
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode