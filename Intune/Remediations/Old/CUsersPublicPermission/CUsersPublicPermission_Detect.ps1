#=============================================================================================================================
# Script Name:     CUsersPublicPermission_Detect.ps1
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
$permissions = (get-acl $directory).Access
#$permissions


$foundINTERACTIVE = $false
foreach($permission in $permissions) {
    $value = $permission.IdentityReference.Value
    #$value
    $NTAccount = New-Object System.Security.Principal.NTAccount($value)
    $SID = $NTAccount.Translate([System.Security.Principal.SecurityIdentifier])
    # NT AUTHORITY\INTERACTIVE (S-1-5-4)
    if($SID.value -eq 'S-1-5-4') {
        $foundINTERACTIVE = $true
    }
}

if ($foundINTERACTIVE) {
    Write-Host "Permissions not OK"
    exit 1
}
else {
    Write-Host "Permissions OK"
    exit 0
}