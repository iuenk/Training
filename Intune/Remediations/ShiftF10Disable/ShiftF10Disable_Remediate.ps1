#=============================================================================================================================
# Script Name:     ShiftF10Disable_Remediate.ps1
# Description:     Remediate Shift+F10 disablement on the device
#   
# Notes      :     Remediate Shift+F10 disablement on the device
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$Path = "$env:SystemRoot\Setup\Scripts"
$Tag = "DisableCMDRequest.TAG"

If (-not(Test-Path -Path "$Path" -PathType Container)) {New-Item -Path $Path -ItemType Directory}
If (-not(Test-Path -Path "$Path\$Tag" -PathType Leaf)) {New-Item -Path $Path -Name $Tag -ItemType File}