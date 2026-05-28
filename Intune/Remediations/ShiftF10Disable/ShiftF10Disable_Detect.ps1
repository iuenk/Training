#=============================================================================================================================
# Script Name:     ShiftF10Disable_Detect.ps1
# Description:     Check if Shift+F10 is disabled on the device
#   
# Notes      :     Check if Shift+F10 is disabled on the device
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$Path = "$env:SystemRoot\Setup\Scripts"
$Tag = "DisableCMDRequest.TAG"

If (Test-Path -Path "$Path\$Tag" -PathType Leaf) {
    Write-Output "[$Tag] exist"
    Exit 0
} Else {
    Write-Output "[$Tag] not exist"
    Exit 1
}