#=============================================================================================================================
# Script Name:     ConfigureAppInstaller_Remediate.ps1
# Description:     Configure policies for the AppInstaller so users have limited possibilities with Winget commands
#   
# Notes      :     Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "RemoveWindowsStore" -Value 1 en RequirePrivateStoreOnly 1
#                  Can only be applied on machine level otherwise getting software from Intune related to Winget apps are not working   
#
# Created by :     Ivo Uenk
# Date       :     06-03-2023
# Version    :     1.0
#=============================================================================================================================

$EC = @()
$ScriptName = 'ConfigureAppInstaller_Remediate'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"
$Target = 'HKLM:\Software\Policies\Microsoft\Windows\AppInstaller'

[hashtable]$RegKeys = @{
  "EnableAllowedSources" = 0
  "EnableAppInstaller" = 1
  "EnableDefaultSource" = 0
  "EnableMicrosoftStoreSource" = 1
  "EnableAdditionalSources" = 0
  "EnableSettings" = 0
 }

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
If (-Not (Test-Path -Path $Target) ) {New-Item -Path $Target -Force}

[hashtable]$GetRegKeys = @{}
Get-Item $Target |
    Select-Object -ExpandProperty Property |
    ForEach-Object {
        $GetRegKeys.Add($_, (Get-ItemProperty -Path $Target -Name $_).$_)
    }

# Check if hashtables are the same
$RegKeys.GetEnumerator() | Select-Object Key, @{ n='Value'; e={$GetRegKeys[$_.Name]}}
$ComparedRegKeys = $RegKeys.GetEnumerator() | ForEach-Object{[PSCustomObject]@{aKey=$_.Key;aValue=$_.Value;bValue=$GetRegKeys[$_.Name]}}

foreach ($Key in $ComparedRegKeys){
    if ($Key.aValue -ne $Key.bValue){
        Write_Log -Message_Type "INFO" -Message "Remediate reg key [$($Key.aKey)] value [$($Key.aValue)]"
        Set-ItemProperty -Path $Target -Name $Key.aKey -Value $Key.aValue -Type DWord
    }
}

#Detect
If (Test-Path -Path $Target) {

    [hashtable]$GetRegKeys = @{}
    Get-Item $Target |
        Select-Object -ExpandProperty Property |
        ForEach-Object {
            $GetRegKeys.Add($_, (Get-ItemProperty -Path $Target -Name $_).$_)
    }

    # Check if hashtables are the same
    $RegKeys.GetEnumerator() | select Key, @{ n='Value'; e={$GetRegKeys[$_.Name]}}
    $ComparedRegKeys = $RegKeys.GetEnumerator() | ForEach-Object{[PSCustomObject]@{aKey=$_.Key;aValue=$_.Value;bValue=$GetRegKeys[$_.Name]}}

    $Count = 0
    # when aValue and bValue are the same
    foreach ($Key in $ComparedRegKeys){
        if ($Key.aValue -eq $Key.bValue){
            $Count += 1
        }
    }
     	
	If ($Count -eq 6) {
		Write_Log -Message_Type "INFO" -Message "All values are correct";$EC += 0}
	ElseIf ($Count -ne 6) {
		Write_Log -Message_Type "ERROR" -Message "Mismatch between registry keys and values"; $EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist" -ForegroundColor Red
    $EC += 1
}

$ExitCode = ($EC | Measure-Object -Sum).Sum
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode