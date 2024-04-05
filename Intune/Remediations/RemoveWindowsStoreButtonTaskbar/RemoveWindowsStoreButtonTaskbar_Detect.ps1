#=============================================================================================================================
# Script Name:     RemoveWindowsStoreButtonTaskbar_Detect.ps1
# Description:     This script will detect if Windows Store button is pinned to Taskbar
#   
# Notes      :     Only tested on Windows 10 
#
# Created by :     Ivo Uenk
# Date       :     28-6-2021
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'W10_RemoveWindowsStoreButtonFromStartMenu_Detection_1.0'
$SystemRoot = $env:SystemRoot
$Log_File = "$SystemRoot\Debug\$ScriptName.log"


$PatternSID = 'S-1-12-1-\d+-\d+\-\d+\-\d+$'
#$PatternSID = 'S-1-5-21-\d+-\d+\-\d+\-\d+$'
$SIDs = (Get-ChildItem Registry::HKEY_USERS | Where-Object {$_.PSChildName -match $PatternSID}).PSChildName


$properConfigurationOfStore= '1'
$getStoreButton = 'NoPinningStoreToTaskbar'
$RegPathPart = 'Software\Policies\Microsoft\Windows\Explorer'

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

If (Test-Path -Path $Log_File) {
    If ((Get-Item -Path $Log_File).Length -gt '100000') {Remove-Item -Path $Log_File -Force}
}

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName DETECT ############################"

ForEach ($SID in $SIDs) {
    Write_Log -Message_Type "INFO" -Message "SID: [$SID]"
    $RegPath = "$SID\$RegPathPart"
    If (Test-Path -Path Registry::HKEY_USERS\$RegPath) 
    {

        $getCurrentConfiguration = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($getStoreButton)

        If ($getCurrentConfiguration -eq $properConfigurationOfStore) {
            Write_Log -Message_Type "INFO" -Message "Value is proper, nothing to change"
            $EC += 0
        } 
        Elseif ($getCurrentConfiguration -eq $null)
        {
            Write_Log -Message_Type "ERROR" -Message "Key is not exist, need to create"
            $EC += 1
        } 
        Else 
        {
            Write_Log -Message_Type "ERROR" -Message "Value need to be changed"
            $EC += 1
        }
    } 
    Else { 
        Write_Log -Message_Type "ERROR" -Message "Path [$RegPath] not exist" -ForegroundColor Red
        $EC += 1
    }
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode