#=============================================================================================================================
# Script Name:     UpdateHealthTools_Remediate.ps1
# Description:     Detect if the Microsoft Update Health Tools are installed
#   
# Notes      :     https://github.com/SMSAgentSoftware/MEM/tree/main/Microsoft%20Update%20Health%20Tools   
#
# Created by :     Ivo Uenk
# Date       :     20-2-2021
# Version    :     1.0
#=============================================================================================================================

$logfilepath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Microsoft_Update_Health_Tools.log"

function WriteToLogFile ($message)
{
   #$timestamp = [DateTime]::UtcNow.ToString('r')
   # we need to get the time via command box, because powershell Get-Date will convert it back in relation to time zone.
   $timestamp = cmd /c echo  %date%-%time% '2>&1'

   $message = "[" + $timestamp + "] " + $message 
   Add-content $logfilepath -value $message
}

# variables
$DownloadDirectory = "$env:Temp"
$DownloadFileName = "Expedite_packages.zip"
$LogDirectory = "$env:Temp"
$LogFile = "UpdateTools.log"

# Get the download URL
$ProgressPreference = 'SilentlyContinue'
$URL = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=103324"
$Request = Invoke-WebRequest -Uri $URL -UseBasicParsing
$DownloadURL = ($Request.Links | Where-Object {$_.outerHTML -match "click here to download manually"}).href

# Download and extract the ZIP package
Invoke-WebRequest -Uri $DownloadURL -OutFile "$DownloadDirectory\$DownloadFileName" -UseBasicParsing
If (Test-Path "$DownloadDirectory\$DownloadFileName")
{
    Expand-Archive -Path "$DownloadDirectory\$DownloadFileName" -DestinationPath $DownloadDirectory -Force
}
else 
{
    Write-Host "Update tools not downloaded"
    WriteToLogFile "Update tools not downloaded"
    Exit 1
}

# Determine which cab to use
[int]$CurrentBuild = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" | Select-Object -ExpandProperty CurrentBuildNumber
Switch ($CurrentBuild)
{
    17763 {$dir = "1809"}
    18363 {$dir = "1909"}
    default {$dir = "2004 and above"}
}
[string]$Bitness = Get-CimInstance Win32_OperatingSystem -Property OSArchitecture | Select-Object -ExpandProperty OSArchitecture
Switch ($Bitness)
{
    "64-bit" {$arch = "x64"}
    "32-bit" {$arch = "x86"}
    default { Write-Host "Unable to determine OS architecture"; Exit 1 }
}
$CabLocation = "$DownloadDirectory\$($DownloadFileName.Split('.')[0])\$dir\$arch"
$CabName = (Get-ChildItem $CabLocation -Name *.cab).pschildname

# Expand the cab and get the MSI
expand.exe /r "$CabLocation\$CabName" /F:* $DownloadDirectory
$File = Get-Childitem -Path $DownloadDirectory\*.msi -File | where {((Get-Date).ToUniversalTime() - $_.CreationTimeUTC).TotalSeconds -lt 10}

# Install the MSI
$Process = Start-Process -FilePath msiexec.exe -ArgumentList "/i $($File.FullName) /qn REBOOT=ReallySuppress /L*V ""$LogDirectory\$LogFile""" -Wait -PassThru
If ($Process.ExitCode -eq 0)
{
    Write-Host "Microsoft Update Health tools successfully installed"
    WriteToLogFile "Microsoft Update Health tools successfully installed"
    Exit 0
}
else 
{
    Write-Host "Microsoft Update Health tools installation failed with exit code $($Process.ExitCode)"
    WriteToLogFile "Microsoft Update Health tools installation failed with exit code $($Process.ExitCode)"
    Exit 1
}