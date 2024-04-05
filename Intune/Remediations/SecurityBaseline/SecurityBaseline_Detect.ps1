#=============================================================================================================================
# Script Name:     SecurityBaseline_Detect.ps1
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
$ScriptName = 'SecurityBaseline_Detect'
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

If (Test-Path -Path $Log_File) {
    If ((Get-Item -Path $Log_File).Length -gt '100000') {Remove-Item -Path $Log_File -Force}
}

Write_Log -Message_Type "INFO" -Message "############################ $ScriptName DETECT ############################"

############################ Disable anonymous access to named pipes/shared, anonymous enumeration of SAM accounts, non-admin remote access to SAM ############################

[hashtable]$RegKeys = @{
    "TokenLeakDetectDelaySecs" = 30
    "RestrictAnonymousSAM" = 1
    "RestrictAnonymous" = 1
    "RestrictRemoteSAM" = "O:BAG:BAD:(A;;RC;;;BA)"
    "LmCompatibilityLevel" = 1
    "LimitBlankPasswordUse" = 1
    "RunAsPPL" = 1
}

$Target = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

If (Test-Path -Path $Target) {

    [hashtable]$GetRegKeys = @{}
    Get-Item $Target |
        Select-Object -ExpandProperty Property |
        ForEach-Object {
            $GetRegKeys.Add($_, (Get-ItemProperty -Path $Target -Name $_).$_)
    }

    $RegKeys.GetEnumerator() | Select-Object Key, @{ n='Value'; e={$GetRegKeys[$_.Name]}}
    $ComparedRegKeys = $RegKeys.GetEnumerator() | ForEach-Object{[PSCustomObject]@{aKey=$_.Key;aValue=$_.Value;bValue=$GetRegKeys[$_.Name]}}

    $Count = 0
    foreach ($Key in $ComparedRegKeys){
        if ($Key.aValue -eq $Key.bValue){
            $Count += 1
        }
    }
     	
	If ($Count -eq $RegKey.count) {
		Write_Log -Message_Type "INFO" -Message "All values are correct";$EC += 0}
	ElseIf ($Count -ne $RegKeys.count) {
		Write_Log -Message_Type "ERROR" -Message "Mismatch between registry keys and values"; $EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC = 1}

############################ Harden lsass to help protect against credential dumping (mimikatz) and audit lsass access requests ############################

$CorrectRegValue = '0'
$RegKey = 'UseLogonCredential'
$Target = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist" -ForegroundColor Red
    $EC += 1
}

$CorrectRegValue = '1'
$RegKey = 'AllowProtectedCreds'
$Target = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

$CorrectRegValue = '00000008'
$RegKey = 'AuditLevel'
$Target = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

############################ Disable autorun/autoplay on all drives ############################
[hashtable]$RegKeys = @{
    "NoDriveTypeAutoRun" = 255
    "NoAutorun" = 1
}

$Target = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\Explorer'

If (Test-Path -Path $Target) {

    [hashtable]$GetRegKeys = @{}
    Get-Item $Target |
        Select-Object -ExpandProperty Property |
        ForEach-Object {
            $GetRegKeys.Add($_, (Get-ItemProperty -Path $Target -Name $_).$_)
    }

    $RegKeys.GetEnumerator() | Select-Object Key, @{ n='Value'; e={$GetRegKeys[$_.Name]}}
    $ComparedRegKeys = $RegKeys.GetEnumerator() | ForEach-Object{[PSCustomObject]@{aKey=$_.Key;aValue=$_.Value;bValue=$GetRegKeys[$_.Name]}}

    $Count = 0
    foreach ($Key in $ComparedRegKeys){
        if ($Key.aValue -eq $Key.bValue){
            $Count += 1
        }
    }
     	
	If ($Count -eq $RegKeys.count) {
		Write_Log -Message_Type "INFO" -Message "All values are correct";$EC += 0}
	ElseIf ($Count -ne $RegKeys.count) {
		Write_Log -Message_Type "ERROR" -Message "Mismatch between registry keys and values"; $EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

$CorrectRegValue = '1'
$RegKey = 'NoAutoplayfornonVolume'
$Target = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

############################ Enable PowerShell Logging ############################

$CorrectRegValue = '1'
$RegKey = 'EnableScriptBlockLogging'
$Target = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

$CorrectRegValue = '1'
$RegKey = 'EnableModuleLogging'
$Target = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'

If (Test-Path -Path $Target){

    $RegValue = (Get-Item -Path $Target).GetValue($RegKey)
		
	If ($RegValue -eq $CorrectRegValue) {
		Write_Log -Message_Type "INFO" -Message "Correct value : [$RegKey : $RegValue]";$EC += 0}
	ElseIf ($null -eq $RegValue ) {
		Write_Log -Message_Type "ERROR" -Message "[$RegKey] not exist"; $EC += 1}
	Else {Write_Log -Message_Type "ERROR" -Message "Wrong value : [$RegKey : $RegValue]";$EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

############################ Disables DNS multicast ############################

[hashtable]$RegKeys = @{
    "EnableMulticast" = 0
    "DisableSmartNameResolution" = 1
}

$Target = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'

If (Test-Path -Path $Target) {

    [hashtable]$GetRegKeys = @{}
    Get-Item $Target |
        Select-Object -ExpandProperty Property |
        ForEach-Object {
            $GetRegKeys.Add($_, (Get-ItemProperty -Path $Target -Name $_).$_)
    }

    $RegKeys.GetEnumerator() | Select-Object Key, @{ n='Value'; e={$GetRegKeys[$_.Name]}}
    $ComparedRegKeys = $RegKeys.GetEnumerator() | ForEach-Object{[PSCustomObject]@{aKey=$_.Key;aValue=$_.Value;bValue=$GetRegKeys[$_.Name]}}

    $Count = 0
    foreach ($Key in $ComparedRegKeys){
        if ($Key.aValue -eq $Key.bValue){
            $Count += 1
        }
    }
     	
	If ($Count -eq $RegKeys.count) {
		Write_Log -Message_Type "INFO" -Message "All values are correct";$EC += 0}
	ElseIf ($Count -ne $RegKeys.count) {
		Write_Log -Message_Type "ERROR" -Message "Mismatch between registry keys and values"; $EC += 1}

} Else { 
    Write_Log -Message_Type "ERROR" -Message "Path [$Target] not exist"; $EC += 1}

############################ Removing Powershell 2.0 ############################

$State = (Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root).State

if ($State -eq "Disabled"){
    Write_Log -Message_Type "INFO" -Message "PowerShell 2.0 is disabled";$EC += 0}
else {
    Write_Log -Message_Type "ERROR" -Message "PowerShell 2.0 not disabled"; $EC += 1}

############################ Enable PUA protection ############################

$PUAProtection = (Get-MpPreference).PUAProtection

if ($PUAProtection -eq 1){
    Write_Log -Message_Type "INFO" -Message "PUA protection enabled";$EC += 0}
else {
    Write_Log -Message_Type "ERROR" -Message "PUA protection not in enabled mode"; $EC += 1}

############################ Filtering Platform Packet Drop and Filtering Platform Connection ############################

$dll = [string]::Join("`r`n", '[DllImport("advapi32.dll")]', 'public static extern bool') 
$auditpol = Add-Type -Name 'AuditPol' -Namespace 'Win32' -PassThru -MemberDefinition "
$dll AuditEnumerateCategories(out IntPtr catList, out uint count);
$dll AuditLookupCategoryName(Guid catGuid, out string catName);
$dll AuditEnumerateSubCategories(Guid catGuid, bool all, out IntPtr subList, out uint count);
$dll AuditLookupSubCategoryName(Guid subGuid, out String subName);
$dll AuditQuerySystemPolicy(Guid subGuid, uint count, out IntPtr policy);
$dll AuditFree(IntPtr buffer);"

Add-Type -TypeDefinition "
using System;
public struct AUDIT_POLICY_INFORMATION {
    public Guid AuditSubCategoryGuid;
    public UInt32 AuditingInformation;
    public Guid AuditCategoryGuid;
}"

function getPolicyInfo($sub) {
    # get policy info for one subcategory:
    $pol = new-object AUDIT_POLICY_INFORMATION
    $size = $ms::SizeOf($pol)
    $ptr  = $ms::AllocHGlobal($size)
    $null = $ms::StructureToPtr($pol, $ptr, $false)
    $null = $auditpol::AuditQuerySystemPolicy($sub, 1, [ref]$ptr)
    $pol  = $ms::PtrToStructure($ptr, [type][AUDIT_POLICY_INFORMATION])
    $null = $ms::FreeHGlobal($ptr)
    [PsCustomObject]@{
        category = $pol.AuditCategoryGuid
        success  = [bool]($pol.AuditingInformation -band 1)
        failure  = [bool]($pol.AuditingInformation -band 2)
    }
}

# (optional) get GUID and local name of all categories:
$ms = [System.Runtime.InteropServices.Marshal]
$count = [uint32]0
$buffer = [IntPtr]::Zero
$size = $ms::SizeOf([type][guid])
$null = $auditpol::AuditEnumerateCategories([ref]$buffer,[ref]$count)
$ptr = [int64]$buffer
$name = [System.Text.StringBuilder]::new()
$catList = @{}
foreach($id in 1..$count) {
    $guid = $ms::PtrToStructure([IntPtr]$ptr,[type][guid])
    $null = $auditpol::AuditLookupCategoryName($guid,[ref]$name)
    $catList[$guid] = $name
    $ptr += $size
}
$null = $auditpol::AuditFree($buffer)

# get all subcategories (with optional name):
$guid = [guid]::Empty
$null = $auditpol::AuditEnumerateSubCategories($guid, $true, [ref]$buffer, [ref]$count)
$ptr = [int64]$buffer
$subList = @{}
foreach($id in 1..$count) {
    $guid = $ms::PtrToStructure([IntPtr]$ptr,[type][guid])
    $null = $auditpol::AuditLookupSubCategoryName($guid,[ref]$name)
    $pol  = getPolicyInfo $guid
    $data = [psCustomObject]@{
        category = $catList[$pol.category]
        subcategory = $name
        success = $pol.success
        failure = $pol.failure
    }
    $subList[$guid.guid] = $data
    $ptr += $size
}
$null = $auditpol::AuditFree($buffer)

# listing all subCategories and their audit settings:
$subList.Values | Sort-Object category, subcategory | Format-Table -AutoSize

# Filtering Platform Packet Drop
$PlatformPacketDrop = $subList['0CCE9225-69AE-11D9-BED3-505054503030']
if(($PlatformPacketDrop.success -eq "True") -and ($PlatformPacketDrop.failure -eq "True")){
    Write_Log -Message_Type "INFO" -Message "Filtering Platform Packet Drop is configured";$EC += 0}
else {
    Write_Log -Message_Type "ERROR" -Message "Filtering Platform Packet Drop is not configured"; $EC += 1}

# Filtering Platform Connection
$PlatformConnection = $subList['0CCE9226-69AE-11D9-BED3-505054503030']
if(($PlatformConnection.success -eq "True") -and ($PlatformConnection.failure -eq "True")){
    Write_Log -Message_Type "INFO" -Message "Filtering Platform Connection is configured";$EC += 0}
else {
    Write_Log -Message_Type "ERROR" -Message "Filtering Platform Connection is not configured"; $EC += 1}

# this is going to be true or false
if($EC -eq 0){
    $ExitCode = 0
}
else {
    $ExitCode = 1
}
    
Write_Log -Message_Type "INFO" -Message "Exit code : $ExitCode"
Exit $ExitCode