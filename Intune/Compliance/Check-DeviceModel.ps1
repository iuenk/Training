<#
Version: 1.0
Author: Ivo Uenk
Script: Check-DeviceModel
Description: Check if device model is in list
#> 

$cModel = $false

$mList = "HP Elite SFF 600 G9 Desktop PC,HP Elite x360 830 13 inch G9 2-in-1 Notebook PC,HP EliteBook 840 14 inch G9 Notebook PC,HP EliteBook 840 G5,HP EliteBook 840 G6,HP EliteBook 840 G7 Notebook PC,HP EliteBook 840 G8 Notebook PC,HP EliteBook 845 14 inch G9 Notebook PC,HP EliteBook 845 G7 Notebook PC,HP EliteBook 845 G8 Notebook PC,HP EliteBook x360 830 G6,HP EliteBook x360 830 G7 Notebook PC,HP EliteBook x360 830 G8 Notebook PC,HP ProDesk 600 G4 SFF,HP ProDesk 600 G5 SFF,HP ProDesk 600 G6 Small Form Factor PC,HP Z4 G4 Workstation,HP ZBook Power 15.6 inch G8 Mobile Workstation PC,HP ZBook Power 15.6 inch G9 Mobile Workstation PC,HP ZBook Power G7 Mobile Workstation,Latitude 7480,Virtual Machine,VMware Virtual Platform"
$cList = $mList.Split(",")

if((Get-CimInstance Win32_ComputerSystemProduct).Name -cin $cList){
    $cModel = $true
}

$output = @{cModel = $cModel}
return $output | convertTo-Json -Compress