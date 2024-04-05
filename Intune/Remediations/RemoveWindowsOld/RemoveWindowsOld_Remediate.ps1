#=============================================================================================================================
# Script Name:     RemoveWindowsOld_Remediate.ps1
# Description:     Detects if C:\Windows.old directory left over is present and older than 5 days on the device
#   
# Notes      :       
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$Path = 'C:\Windows.old'

$delay = 30 # milliseconds
$retries = 10


# Work-around for Remove-Item : Cannot remove item C:\Windows.old\xxxxx The directory is not empty. errors
# Work-around for the "Remove-Item: Access to the cloud file is denied" error
# Basically removed the native powershell code Remove-Item -Recurse as it is not reliable
# https://serverfault.com/questions/199921/force-remove-files-and-directories-in-powershell-fails-sometimes-but-not-always

$fullPath = (Resolve-Path $path).ProviderPath

# https://stackoverflow.com/questions/329355/cannot-delete-directory-with-directory-deletepath-true
#[IO.Directory]::Delete($fullPath, $true)


try
{
    [IO.Directory]::Delete($fullPath, $true)   
}

catch [System.IO.IOException]
{
        # Windows.old are system files, hence more protected by Windows, we need to take ownership to overrule Access Denied errors
        Write-Host "System.IO.IOException running native"
        &cmd.exe /c takeown /F $fullPath /A /R /D Y
        &cmd.exe /c icacls $fullPath /T /grant administrators:F
        &cmd.exe /c rd /s /q $fullPath

}
