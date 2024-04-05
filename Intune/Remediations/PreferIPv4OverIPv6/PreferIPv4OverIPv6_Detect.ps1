#=============================================================================================================================
# Script Name:     PreferIPv4OverIPv6_Detect.ps1
# Description:     A script to detect if RegKey is set to prefer IPv4 over IPv6
#   
# Notes      :   
#
# Created by :     Ivo Uenk
# Date       :     14-2-2022
# Version    :     1.0
#=============================================================================================================================

### Actions to check if device is in ESP; if so Exit 0 to skip actions ###
$Regpath = "HKLM:\Software\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup"
$Regkey = "HasProvisioningCompleted"

If (Get-Process -Name 'CloudExperienceHostBroker' -ErrorAction SilentlyContinue) {$CloudExpBroker = $true }
If (((Get-Item $regpath -EA Ignore).Property -contains $regkey) -eq $false) {$regcheck = $true}
If (($CloudExpBroker -eq $true) -and ($regcheck -eq $true)) {
    write-host "in ESP"
    Exit 0
    }


$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\"
$RegKey = "DisabledComponents"
$RegValue = 32
$GetRegValue = (Get-Item -Path $RegPath).GetValue($RegKey)

If ($GetRegValue -eq $RegValue) {
    Write-host "Correct value : $GetRegValue"
    Exit 0
} Elseif ($null -eq $GetRegValue){
    Write-host "Not exist"
    Exit 1
} Else {
    Write-host "Wrong value : $GetRegValue"
    Exit 1
}