#=============================================================================================================================
# Script Name:     DisableHardwareAcceleration_Detect.ps1
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
$Found=$false
$FoundText=$null

## Check for Google Chrome
If (Test-Path -Path $ChromeRegPath -PathType Container) {
    $RegKeyValue = (Get-ItemProperty -Path $ChromeRegPath -Name $RegKey -ErrorAction SilentlyContinue)
    If ($RegKeyValue) {
        $Found=$true
		$FoundText="Chrome"
    }
} 
## Check for Edge
If (Test-Path -Path $EdgeRegPath -PathType Container) {
	$RegKeyValue = (Get-ItemProperty -Path $EdgeRegPath -Name $RegKey -ErrorAction SilentlyContinue)
	If ($RegKeyValue) {
		$Found=$true
		if ($FoundText) {
			$FoundText+=" and Edge"
		} else {
			$FoundText="Edge"
		}
	}
}

if ($Found) {
	Write-Host "Registry Key [$RegKey] exist for $FoundText. Remediation required."
	Exit 1
} else { 
	Write-Host "Registry Key [$RegKey] does not exist in Registry Path [$ChromeRegPath] or [$EdgeRegPath]."
}
Exit 0


