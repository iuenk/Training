#=============================================================================================================================
# Script Name:     Set-RestartButtonCPC.ps1
# Description:     This script will add the restart option to the start menu on a Cloud PC
#   
# Notes      :     By default users do not have the option to restart it directly from the Cloud PC     
#                  With this script they do have the option to restart it directly from start menu
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$RegCheck = 'RestartButtonCPC'
$version = 1
$RegRoot= "HKLM"
if (Test-Path "$RegRoot`:\Software\Ucorp") {
    try{
        $regexist = Get-ItemProperty "$RegRoot`:\Software\Ucorp" -Name $RegCheck -ErrorAction Stop
    }catch{
        $regexist = $false
    }
} 
else {
    New-Item "$RegRoot`:\Software\Ucorp"
}    
if ((!($regexist)) -or ($regexist.$RegCheck -lt $Version)) {
    try{
        $user = "Users"
        $tmp = [System.IO.Path]::GetTempFileName()
        secedit.exe /export /cfg $tmp
        $settings = Get-Content -Path $tmp
        $account = New-Object System.Security.Principal.NTAccount($user)
        $sid =   $account.Translate([System.Security.Principal.SecurityIdentifier])
        for($i=0;$i -lt $settings.Count;$i++){
            if($settings[$i] -match "SeShutdownPrivilege")
            {
                $settings[$i] += ",*$($sid.Value)"
            }
        }
        $settings | Out-File $tmp
        secedit.exe /configure /db secedit.sdb /cfg $tmp  /areas User_RIGHTS
        Remove-Item -Path $tmp
    }
    catch{
        write-error 'Unable to add the users group to Shut down the system policy'
        break 
    }

    if(!($regexist)){
        New-ItemProperty "$RegRoot`:\Software\Ucorp" -Name $RegCheck -Value $Version -PropertyType string
    }else{
        Set-ItemProperty "$RegRoot`:\Software\Ucorp" -Name $RegCheck -Value $version
    }
}