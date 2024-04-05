#=============================================================================================================================
# Script Name:     CDrivePermissions_Detect.ps1
# Description:     Script to detect the permissions on C: Drive for authenticated users
#   
# Notes      :     It prohibits authenticated users from saving files to the root of C: and changes the permissions for Users 
#                  group to read and execute     
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$ScriptName = 'C_Drive_Permissions'
$Directory = 'C:\'
$InvalidPermissionFound = $false
$Output = ''

$Phase = 'DETECTION'
$LogFile = $env:ProgramData + '\Microsoft\IntuneManagementExtension\Logs\' + $ScriptName + '.log'

#region Functions
    #region Write-Log
    Function Write-Log
	    {
	    param(
	    $MessageType, 
	    $Message
	    )
		    $MyDate = "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)  
		    Add-Content $LogFile  "$MyDate - $MessageType : $Message"  
	    }
    #endregion

    #region Exit-Script
    Function Exit-Script
	    {
	    param(
	    $ExitCode
	    )
		     Write-Log -MessageType "INFO" -Message "Script finished with exit code: [$ExitCode]"
             Write-Log -MessageType "INFO" -Message "===================================================="
             #Break
             Exit $ExitCode
	    }  
    #endregion
#endregion

If (Test-Path -Path $LogFile -PathType Leaf) {
    If ((Get-Item -Path $LogFile).Length -gt '10000') {Remove-Item -Path $LogFile -Force}
}

Write-Log -MessageType "INFO" -Message "==================$Phase=================="

(Get-Acl $Directory).Access | ForEach-Object {
    If ([string]::IsNullOrEmpty($Output)) { $Output = "[$($_.IdentityReference) - $($_.AccessControlType) - $($_.FileSystemRights)]"}
    Else { $Output = $Output + ' ' + "[$($_.IdentityReference) - $($_.AccessControlType) - $($_.FileSystemRights)]"}

    Write-Log -MessageType "INFO" -Message "$($_.IdentityReference) - $($_.AccessControlType) - $($_.FileSystemRights)"
    #Write-Host "$($_.IdentityReference)" -ForegroundColor Green

    If (($_.IdentityReference.value).startswith('S-1-15-3-')) {
        #Write-Host 'S-1-15-3-'
    } Else {
        $NTAccount = New-Object System.Security.Principal.NTAccount($_.IdentityReference.value)
        $SID = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])
        #Write-Host "$($SID.value)" -ForegroundColor Green
        If($SID.value -eq 'S-1-5-11') {
            $InvalidPermissionFound = $true
            Write-Log -MessageType "WARNING" -Message "Authenticated Users SID [S-1-5-11] has been found. Remediation required."
        }
        ElseIf ($SID.value -eq 'S-1-5-32-545') {
            If (($_.FileSystemRights -ne 'ReadAndExecute, Synchronize')) {
                $InvalidPermissionFound = $true
                Write-Log -MessageType "WARNING" -Message "Users SID [S-1-5-32-545] have incorrect permissions. Remediation required."
            }
        }
    }
}

If ($InvalidPermissionFound) {
    $Output = "Permissions on the [$Directory] drive are not set correctly. Remediation required. " + $Output
    Write-Host "$Output"
    Exit-Script 1
}
Else {
    $Output = "Permissions on the [$Directory] drive are set correctly. " + $Output
    Write-Host "$Output"
    Exit-Script 0
}