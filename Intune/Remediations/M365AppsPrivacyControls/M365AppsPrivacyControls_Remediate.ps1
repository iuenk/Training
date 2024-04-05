#=============================================================================================================================
# Script Name:     M365AppsPrivacyControls_Remediate.ps1
# Description:     
#   
# Notes      :   
#
# Created by :     Ivo Uenk
# Date       :     28-6-2021
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'W10_M365Apps_PrivacyControls_1.0'
$SystemRoot = $env:SystemRoot
$Log_File = "$SystemRoot\Debug\$ScriptName.log"


$PatternSID = 'S-1-12-1-\d+-\d+\-\d+\-\d+$'
#$PatternSID = 'S-1-5-21-\d+-\d+\-\d+\-\d+$'
$SIDs = (Get-ChildItem Registry::HKEY_USERS | Where-Object {$_.PSChildName -match $PatternSID}).PSChildName


$RegValueUserContentDisabled= '2'
$RegKeyUserContentDisabled = 'usercontentdisabled'
$RegPathPart = 'Software\Policies\Microsoft\office\16.0\common\privacy'

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

    $GetUserContentDisabled = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($RegKeyUserContentDisabled)
    Write_Log -Message_Type "INFO" -Message "[$RegKeyUserContentDisabled : $GetUserContentDisabled]"
    If ($GetUserContentDisabled -ne $RegValueUserContentDisabled) {
        Write_Log -Message_Type "INFO" -Message 'Remediate'
        Set-ItemProperty -Path Registry::HKEY_USERS\$RegPath -Name $RegKeyUserContentDisabled -Value $RegValueUserContentDisabled -Type DWord
    } 
}

#Detect
ForEach ($SID in $SIDs) {
    Write_Log -Message_Type "INFO" -Message "SID: [$SID]"
    $RegPath = "$SID\$RegPathPart"
    If (Test-Path -Path Registry::HKEY_USERS\$RegPath) {

        $GetUserContentDisabled = (Get-Item -Path Registry::HKEY_USERS\$RegPath).GetValue($RegKeyUserContentDisabled)
		
		If ($GetUserContentDisabled -eq $RegValueUserContentDisabled) {
			Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKeyUserContentDisabled : $GetUserContentDisabled]";$EC += 0}
		ElseIf ($GetUserContentDisabled -eq $null ) {
			Write_Log -Message_Type "ERROR" -Message "[$RegKeyUserContentDisabled] not exist"; $EC += 1}
		Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKeyDisconnectedState : $GetRegValueDisconnectedState], [$RegKeyUserContentDisabled : $GetUserContentDisabled]";$EC += 1}

    } Else { 
        Write_Log -Message_Type "ERROR" -Message "Path [$RegPath] not exist" -ForegroundColor Red
        $EC += 1
    }
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode