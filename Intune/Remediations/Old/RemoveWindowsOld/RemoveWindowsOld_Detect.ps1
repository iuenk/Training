#=============================================================================================================================
# Script Name:     RemoveWindowsOld_Detect.ps1
# Description:     Detects if C:\Windows.old directory left over is present and older than 5 days on the device
#   
# Notes      :       
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$path = 'C:\Windows.old'


$safeToDeleteDays = 5
$safeToDeleteDate = (Get-Date).AddDays(-$safeToDeleteDays) 

$items = $null
$items = Get-Item -Path $path| Where-Object LastWriteTime -le $safeToDeleteDate

if ($items -eq $null) {
    Write-Host "$path not found or modified date not older than $safeToDeleteDays days"
    exit 0
}
else {
    Write-Host "$path found and modified date older than $safeToDeleteDays days"
    exit 1
}

