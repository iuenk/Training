#=============================================================================================================================
# Script Name:     UpdateHealthTools_Detect.ps1
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

# Check minimum OS version requirement (1809 or later)
[int]$CurrentBuild = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" | Select-Object -ExpandProperty CurrentBuildNumber
If ($CurrentBuild -notin (17763,18363,19041,19042) -and $CurrentBuild -lt 19043)
{
    Write-Host "Minimum OS version requirement not met"
    WriteToLogFile "Minimum OS version requirement not met"
    Exit 0
}

# Check if Update tools installed
$Results = @()
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($key in $UninstallKeys)
{
    If (Test-Path $key)
    {
        $Entry = (Get-ChildItem -Path $key) | Where-Object {$_.GetValue('DisplayName') -eq "Microsoft Update Health Tools"} 
        If ($Entry)
        {
            foreach ($item in $Entry) 
            {
                $Results += [PSCustomObject]@{
                    DisplayName = $item.GetValue("DisplayName")
                    DisplayVersion = $item.GetValue("DisplayVersion")
                    InstallDate = $item.GetValue("InstallDate")
                    GUID = $item.pschildname
                }
            }
        }
    }
}
If ($Results.Count -ge 1)
{
    foreach ($Result in $Results)
    {
        Write-Host ($Result | ConvertTo-Json -Compress)
        WriteToLogFile ($Result | ConvertTo-Json -Compress)
    }
    Exit 0
}
Else 
{
    Write-Host "Update Tools not found"
    WriteToLogFile "Update Tools not found"
    Exit 1
}