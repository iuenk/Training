#=============================================================================================================================
# Script Name:     PreferIPv4OverIPv6_Remediate.ps1
# Description:     A script to detect if RegKey is set to prefer IPv4 over IPv6
#   
# Notes      :   
#
# Created by :     Ivo Uenk
# Date       :     14-2-2022
# Version    :     1.0
#=============================================================================================================================

$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\"
$RegKey = "DisabledComponents"
$RegValue = 32

Set-ItemProperty -Path $RegPath -Name $RegKey -Value $RegValue