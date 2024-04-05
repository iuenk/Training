#=============================================================================================================================
# Script Name:     Set-EnchanceIntuneAgentLogging.ps1
# Description:     The script extends the Intune Management Extension (IME) log behavior
#   
# Notes      :     LogMaxSize controls the amount of bytes of one log file
#				   LogMaxHistroy controls the amount of files to keep
#				   EventLogMaxSize controls the size of the eventlogs      
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

if (Test-Path HKLM:\Software\Ucorp){
    $regexist = Get-ItemProperty "HKLM:\Software\Ucorp" -Name 'EnchanceIntuneAgentLogging' -ErrorAction SilentlyContinue
}
else {
    New-Item HKLM:\Software\Ucorp -ErrorAction SilentlyContinue
}

if ((!($regexist)) -or ($regexist.Fonts -lt 2)){

	# define log file size in bytes e.g. 4194304 byte -> 4096 KB -> 4 MB
	$logMaxSize = 4194304

	# define event log file size in bytes e.g. 32MB
	$eventlogMaxSize = 33554432

	# define log files to keep
	$logMaxHistory = 10

	# create the registry key path for the IME agent
	$regKeyFullPath = "HKLM:\SOFTWARE\Microsoft\IntuneWindowsAgent\Logging"
	New-Item -Path $regKeyFullPath -Force | Out-Null

	# set value to define new size instead of the default 2 MB
	Set-ItemProperty -Path $regKeyFullPath -Name "LogMaxSize" -Value $logMaxSize -Type String -Force

	# set value to define new amount of logfiles to keep
	Set-ItemProperty -Path $regKeyFullPath -Name "LogMaxHistory" -Value $logMaxHistory -Type String -Force

	# create key in the registry key path for the Event log 
	$regKeyFullPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin"
	# set value to define new size instead of the default 1 MB
	Set-ItemProperty -Path $regKeyFullPath -Name "MaxSize" -Value $eventlogMaxSize -Type DWord -Force

	# create key in the registry key path for the Event log 
	$regKeyFullPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational"
	# set value to define new size instead of the default 1 MB
	Set-ItemProperty -Path $regKeyFullPath -Name "MaxSize" -Value $eventlogMaxSize -Type DWord -Force

	try{
		if(!($regexist)){
			New-ItemProperty HKLM:\Software\Ucorp -Name 'EnchanceIntuneAgentLogging' -Value 1 -PropertyType string -ErrorAction Stop
		}else{
			Set-ItemProperty HKLM:\Software\Ucorp -Name 'EnchanceIntuneAgentLogging' -Value 2 -ErrorAction Stop
		}
	}catch{
		Write-Error 'failed to set the EnchanceIntuneAgentLogging'
	}
}