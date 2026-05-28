#=============================================================================================================================
# Script Name:     DisableHardwareAcceleration_Remediate.ps1
# Description:     Tests if a registry value exists that sets Hardware AccelerationMode Enabled for Edge & Google Chrome browsers and remove the registry keys
#   
# Notes      :   
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$RegKey = 'HardwareAccelerationModeEnabled'
$ChromeRegPath = 'HKLM:\Software\Policies\Google\Chrome'
$EdgeRegPath = 'HKLM:\Software\Policies\Microsoft\Edge'
$KeyRemoved=$false
$KeyRemovedText=$null

If (Test-Path -Path $ChromeRegPath -PathType Container) {
	$RegKeyValue = (Get-ItemProperty -Path $ChromeRegPath -Name $RegKey -ErrorAction SilentlyContinue)
	If ($RegKeyValue) {
		Remove-ItemProperty -Path $ChromeRegPath -Name $RegKey
		$KeyRemoved=$true
		$KeyRemovedText="Chrome"
	}
} 
If (Test-Path -Path $EdgeRegPath -PathType Container) {
	$RegKeyValue = (Get-ItemProperty -Path $EdgeRegPath -Name $RegKey -ErrorAction SilentlyContinue)
	If ($RegKeyValue) {
		Remove-ItemProperty -Path $EdgeRegPath -Name $RegKey
		$KeyRemoved=$true
		if ($KeyRemovedText) {
			$KeyRemovedText+=" and Edge"
		} else {
			$KeyRemovedText="Edge"
		}
	}
}
if ($KeyRemoved) {
	Write-Host "Registry Key [$RegKey] removed for $KeyRemovedText."
} else {
	Write-Host "Registry Key [$RegKey] not removed beacuse it does not exist."
}
