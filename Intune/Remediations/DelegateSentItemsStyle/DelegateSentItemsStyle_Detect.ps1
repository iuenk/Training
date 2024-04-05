#=============================================================================================================================
# Script Name:     DelegateSentItemsStyle_Detect.ps1
# Description:     Items that are send on behave of you from a shared mailbox will only be seen in send items of that shared mailbox
#   
# Notes      : 	   So colleagues can see what emails are send from the shared mailbox  
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'DelegateSentItemsStyle_Detect'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"


$PatternSID = 'S-1-12-1-\d+-\d+\-\d+\-\d+$'
#$PatternSID = 'S-1-5-21-\d+-\d+\-\d+\-\d+$'
$SIDs = (Get-ChildItem Registry::HKEY_USERS | Where-Object {$_.PSChildName -match $PatternSID}).PSChildName

$RegValueDelegateSentItemsStyle = '1'
$RegKeyDelegateSentItemsStyle = 'DelegateSentItemsStyle'
$RegPathPart = 'Software\Microsoft\Office\16.0\Outlook\Preferences'

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
    If ((Get-Item -Path $Log_File).Length -gt '10000') {Remove-Item -Path $Log_File -Force}
}

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName DETECT ############################"

ForEach ($SID in $SIDs) {
    Write_Log -Message_Type "INFO" -Message "SID: [$SID]"
    $RegPath = "$SID\$RegPathPart"
    If (Test-Path -Path Registry::HKEY_USERS\$RegPath) {

        $GetUserDelegateSentItemsStyle = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($RegKeyDelegateSentItemsStyle)
		
		If ($GetUserDelegateSentItemsStyle -eq $RegValueDelegateSentItemsStyle) {
			Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKeyDelegateSentItemsStyle : $GetUserDelegateSentItemsStyle]";$EC += 0}
		ElseIf ($GetUserDelegateSentItemsStyle -eq $null ) {
			Write_Log -Message_Type "ERROR" -Message "[$RegKeyDelegateSentItemsStyle] not exist"; $EC += 1}
		Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKeyDelegateSentItemsStyle : $GetUserDelegateSentItemsStyle]";$EC += 1}

    } Else { 
        Write_Log -Message_Type "ERROR" -Message "Path [$RegPath] not exist" -ForegroundColor Red
        $EC += 1
    }
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode