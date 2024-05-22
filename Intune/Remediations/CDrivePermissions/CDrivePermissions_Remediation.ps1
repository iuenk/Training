#=============================================================================================================================
# Script Name:     CDrivePermissions_Remediate.ps1
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
$ErrorActionPreference = "Stop"

$Phase = 'REMEDIATION'
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

If (-Not(Test-Path -Path $env:SystemRoot\System32\Winevt\Logs\UCORP_CMW.evtx -PathType Leaf)) {
        $logname = "UCORP_CMW"
        $source = "UCORP"
        $log_size_limit = 8MB

        #Create new log and limit size
        New-EventLog -LogName $logname -Source $source -ErrorAction SilentlyContinue | Limit-EventLog -LogName $logname -MaximumSize $log_size_limit
          
        #Create entry in logfile
        Write-EventLog -LogName $logname -Source $source -EntryType Information -Message "Initial Event Log Created" -EventId 1
}

$acl = Get-Acl $Directory
$Output = ''

$acl.Access | ForEach-Object {
    If ([string]::IsNullOrEmpty($Output)) { 
        $Output = "Permissions before running the remediation script: `n`nFileSystemRights : $($_.FileSystemRights)`nAccessControlType : $($_.AccessControlType) `nIdentityReference : $($_.IdentityReference) `nIsInherited : $($_.IsInherited) `nInheritanceFlags : $($_.InheritanceFlags) `nPropagationFlags : $($_.PropagationFlags)"
        }
    Else { 
        $Output = $Output + "`n`n" + "FileSystemRights : $($_.FileSystemRights)`nAccessControlType : $($_.AccessControlType) `nIdentityReference : $($_.IdentityReference) `nIsInherited : $($_.IsInherited) `nInheritanceFlags : $($_.InheritanceFlags) `nPropagationFlags : $($_.PropagationFlags)"
    }
}

New-EventLog -LogName "UCORP_CMW" -Source "C drive permissions"  -ErrorAction SilentlyContinue
Write-EventLog -LogName "UCORP_CMW" -Source "C drive permissions" -EntryType Information -EventId 1 -Message "$Output"


try {
    
    # Administrators (S-1-5-32-544)
    $SID = "S-1-5-32-545"
    $securityidentifier = new-object security.principal.securityidentifier $sid
    $group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
    $admin = New-Object System.Security.AccessControl.FileSystemAccessRule($group,"FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($admin)

    # SYSTEM (S-1-5-18)
    $SID = "S-1-5-18"
    $securityidentifier = new-object security.principal.securityidentifier $sid
    $group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
    $system = New-Object System.Security.AccessControl.FileSystemAccessRule($group,"FullControl","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($system)

    # BUILTIN\Users (S-1-5-32-545)
    $SID = "S-1-5-32-545"
    $securityidentifier = new-object security.principal.securityidentifier $sid
    $group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
    $usersaccess = New-Object System.Security.AccessControl.FileSystemAccessRule($group,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($usersaccess)

    # Remove Authenticated Users (S-1-5-11)"
    $SID = "S-1-5-11"
    $securityidentifier = new-object security.principal.securityidentifier $sid
    $group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
    $acl.PurgeAccessRules($group)

    $acl | Set-ACl $directory
}
catch {Write-Host "An error occurred while setting permission on [$Directory]. $_"
    Write-Log -MessageType "ERROR" -Message "An error occurred while setting permission on [$Directory]"
    Write-Log -MessageType "ERROR" -Message "$_"
    Exit-Script 1
}

Write-Log -MessageType "INFO" -Message "Permission on [$Directory] drive has ben set."


$acl = Get-Acl $Directory

$Output = ''

$acl.Access | ForEach-Object {
    If ([string]::IsNullOrEmpty($Output)) { 
        $Output = "Permissions after running the remediation script: `n`nFileSystemRights : $($_.FileSystemRights)`nAccessControlType : $($_.AccessControlType) `nIdentityReference : $($_.IdentityReference) `nIsInherited : $($_.IsInherited) `nInheritanceFlags : $($_.InheritanceFlags) `nPropagationFlags : $($_.PropagationFlags)"
        }
    Else { 
        $Output = $Output + "`n`n" + "FileSystemRights : $($_.FileSystemRights)`nAccessControlType : $($_.AccessControlType) `nIdentityReference : $($_.IdentityReference) `nIsInherited : $($_.IsInherited) `nInheritanceFlags : $($_.InheritanceFlags) `nPropagationFlags : $($_.PropagationFlags)"
    }
}

New-EventLog -LogName "UCORP_CMW" -Source "C drive permissions"  -ErrorAction SilentlyContinue
Write-EventLog -LogName "UCORP_CMW" -Source "C drive permissions" -EntryType Information -EventId 2 -Message "$Output"

Exit-Script 0