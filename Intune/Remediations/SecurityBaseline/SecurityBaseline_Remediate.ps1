#=============================================================================================================================
# Script Name:     SecurityBaseline_Remediate.ps1
# Description:     This script will configure security settings that are not available in the Intune GUI
#   
# Notes      :     Not all settings are directly available in Intune but are recommended (Microsoft Secure Score)
#                  This script will set the recommended security settings on a device   
#
# Created by :     Ivo Uenk
# Date       :     10-12-2023
# Version    :     1.0
#=============================================================================================================================

$EC = 0
$ScriptName = 'SecurityBaseline_Remediate'
$Log_File = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\$ScriptName.log"

#### Define Write_Log function ####
Function Write_Log
	{
	param(
	$Message_Type, 
	$Message
	)
		$MyDate = "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)  
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message"  
	} 

if (Test-Path -Path $Log_File){
    if ((Get-Item -Path $Log_File).Length -gt '100000') {Remove-Item -Path $Log_File -Force}
}

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName REMEDIATE ############################"

try {
	# Harden lsass to help protect against credential dumping (mimikatz) and audit lsass access requests
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RunAsPPL" -PropertyType "DWORD" -Value 1 -Force
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" -Name "UseLogonCredential" -PropertyType "DWORD" -Value 0 -Force
	
	if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation")){ 
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation" -Force 
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation" -Name "AllowProtectedCreds" -PropertyType "DWORD" -Value 1 -Force
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" -Name "AuditLevel" -PropertyType "DWORD" -Value 00000008 -Force

	# Disable anonymous access to named pipes/shared, anonymous enumeration of SAM accounts, non-admin remote access to SAM
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "TokenLeakDetectDelaySecs" -PropertyType "DWORD" -Value 30 -Force 
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -PropertyType "DWORD" -Value 1 -Force 
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -PropertyType "DWORD" -Value 1 -Force 
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictRemoteSAM" -PropertyType "STRING" -Value "O:BAG:BAD:(A;;RC;;;BA)" -Force 
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -PropertyType "DWORD" -Value 1 -Force 
	New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LimitBlankPasswordUse" -PropertyType "DWORD" -Value 1 -Force 

	# Disables DNS multicast
	if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient")){ 
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Force 
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -PropertyType "DWORD" -Value 0 -Force 
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DisableSmartNameResolution" -PropertyType "DWORD" -Value 1 -Force 

	# Enable PowerShell Logging
	if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging")){ 
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Force 
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -PropertyType "DWORD" -Value 1 -Force  

	if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging")){ 
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Force 
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" -Name "EnableModuleLogging" -PropertyType "DWORD" -Value 1 -Force 

	#Disable autorun/autoplay on all drives
	if (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer")){ 
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Force 
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoAutoplayfornonVolume" -PropertyType "DWORD" -Value 1 -Force

	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer" -Name "NoDriveTypeAutoRun" -PropertyType "DWORD" -Value 255 -Force 
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer" -Name "NoAutorun" -PropertyType "DWORD" -Value 1 -Force 

	$language = (Get-WinSystemLocale).Name
    if ($language -eq "nl-NL"){
        $system = "systeem"
    } else {
        $system = "system"
    }

	# Enable PUA protection
	$PUAProtection = (Get-MpPreference).PUAProtection
	
	if ($PUAProtection -ne 1){
		Set-MpPreference -PUAProtection Enabled
	}

    # Filtering Platform Packet Drop
    Auditpol /set /category:"$system" /SubCategory:"{0CCE9225-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable
    
    # Filtering Platform Connection
    Auditpol /set /category:"$system" /SubCategory:"{0CCE9226-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable

    #Removing Powershell 2.0
	$State = (Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root).State

	if ($State -ne "Disabled"){
		Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root
	}

    Write_Log -Message_Type "INFO" -Message "Security baseline is set"
    $EC += 0
}
catch {
    Write_Log -Message_Type "ERROR" -Message "Failed to set security baseline" -ForegroundColor Red
    $EC += 1
}

# this is going to be true or false
if($EC -eq 0){
    $ExitCode = 0
}
else {
    $ExitCode = 1
}

Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode