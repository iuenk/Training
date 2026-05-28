#=============================================================================================================================
# Script Name:     RemoveWindowsStoreButtonTaskbar_Remediate.ps1
# Description:     This script will detect if Windows Store button is pinned to Taskbar
#   
# Notes      :     Only tested on Windows 10 
#
# Created by :     Ivo Uenk
# Date       :     28-6-2021
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'W10_RemoveWindowsStoreButtonFromStartMenu_Remediate_1.0'
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

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName REMEDIATE ############################"

#Remediate
ForEach ($SID in $SIDs) {
    Write_Log -Message_Type "INFO" -Message "SID: [$SID]"
    $RegPath = "$SID\$RegPathPart"
    If (-Not (Test-Path -Path Registry::HKEY_USERS\$RegPath) ) {New-Item -Path Registry::HKEY_USERS\$RegPath -Force}

    $getCurrentConfiguration = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($getStoreButton)

    If ($getCurrentConfiguration -ne $properConfigurationOfStore) {
        Write_Log -Message_Type "INFO" -Message "Wrong Value, need to be changed."
        Write_Log -Message_Type "INFO" -Message 'Remediate'
        Set-ItemProperty -Path Registry::HKEY_USERS\$RegPath -Name $getStoreButton -Value $properConfigurationOfStore -Type DWord -Force
    } 
}

#Detect
ForEach ($SID in $SIDs) {
    Write_Log -Message_Type "INFO" -Message "SID: [$SID]"
    $RegPath = "$SID\$RegPathPart"
    If (Test-Path -Path Registry::HKEY_USERS\$RegPath) {

        $getCurrentConfiguration = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($getStoreButton)

        If ($getCurrentConfiguration -eq $properConfigurationOfStore) {
            Write_Log -Message_Type "INFO" -Message "Value after Remediate is proper"
            $EC += 0
        } Elseif ($getCurrentConfiguration -eq $null){
            Write_Log -Message_Type "ERROR" -Message "Key is still not exist and need to be created"
            $EC += 1
        } Else {
            Write_Log -Message_Type "ERROR" -Message "Value need to be changed even after Remediate action"
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