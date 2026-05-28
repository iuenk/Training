#=============================================================================================================================
# Script Name:     CUsersPublicPermission_Remediate.ps1
# Description:     A script to detect whether there are permissions applied to NT AUTHORITY\INTERACTIVE on Public Documents folders
#                  If the permissions exist there will be a remediation script triggered
#   
# Notes      :     Switched to using SID to support native non-English OS languages
#
# Created by :     Ivo Uenk
# Date       :     14-1-2023
# Version    :     1.0
#=============================================================================================================================

$directory = "C:\Users\Public"

$acl = Get-Acl $directory

# BUILTIN\Users (S-1-5-32-545)
$SID = "S-1-5-32-545"
$securityidentifier = new-object security.principal.securityidentifier $sid
$group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
$usersaccess = New-Object System.Security.AccessControl.FileSystemAccessRule($group,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
$acl.SetAccessRule($usersaccess)

# NT AUTHORITY\INTERACTIVE (S-1-5-4)
$SID = "S-1-5-4"
$securityidentifier = new-object security.principal.securityidentifier $sid
$group = ( $securityidentifier.translate( [security.principal.ntaccount] ) )
$acl.PurgeAccessRules($group)

$acl | Set-ACl $directory

exit 0