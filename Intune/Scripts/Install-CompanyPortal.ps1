#=============================================================================================================================
# Script Name:    Install-CompanyPortal.ps1
# Description:    Script based on https://oliverkieselbach.com/2020/04/22/how-to-completely-change-windows-10-language-with-intune/
#   
# Notes      :     
#
# Created by :     Ivo Uenk
# Date       :     28-6-2023
# Version    :     1.0
#=============================================================================================================================

$applicationId = "9wzdncrfj3pz"
$packageIdentityName = 'Microsoft.CompanyPortal'
$skuId = 0016

$LogFile = $env:ProgramData + '\Microsoft\IntuneManagementExtension\Logs\' + $packageIdentityName + '_installation-script.log'

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
# https://learn.microsoft.com/en-us/mem/configmgr/protect/deploy-use/find-a-pfn-for-per-app-vpn
$webpage = Invoke-WebRequest -UseBasicParsing -Uri "https://bspmts.mp.microsoft.com/v1/public/catalog/Retail/Products/$applicationId/applockerdata"
$packageFamilyName = ($webpage | ConvertFrom-JSON).packageFamilyName

Write-Log -MessageType 'INFO' -Message "==========[$packageIdentityName][$applicationId]=========="

$Package = Get-AppxPackage -AllUsers -Name $packageIdentityName
If ((-not([string]::IsNullOrEmpty($Package.InstallLocation))) -and (($Package.InstallLocation).StartsWith("$env:ProgramFiles\WindowsApps\$packageIdentityName"))) {
    Write-Log -MessageType INFO -Message "Package [$packageIdentityName] is already installed."
} Else {
    Write-Log -MessageType 'INFO' -Message "WebPage info: $webpage"

    $namespaceName = "root\cimv2\mdm\dmmap"
    $session = New-CimSession
    $omaUri = "./Vendor/MSFT/EnterpriseModernAppManagement/AppInstallation"
    $newInstance = New-Object Microsoft.Management.Infrastructure.CimInstance "MDM_EnterpriseModernAppManagement_AppInstallation01_01", $namespaceName
    $property = [Microsoft.Management.Infrastructure.CimProperty]::Create("ParentID", $omaUri, "string", "Key")

    $newInstance.CimInstanceProperties.Add($property)
    $property = [Microsoft.Management.Infrastructure.CimProperty]::Create("InstanceID", $packageFamilyName, "String", "Key")
    $newInstance.CimInstanceProperties.Add($property)

    $flags = 0
    $paramValue = [Security.SecurityElement]::Escape($('<Application id="{0}" flags="{1}" skuid="{2}"/>' -f $applicationId, $flags, $skuId))
    $params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
    $param = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create("param", $paramValue, "String", "In")
    $params.Add($param)
    
    Write-Log -MessageType 'INFO' -Message "Create the MDM instance and trigger the StoreInstallMethod"
    try {
        # we create the MDM instance and trigger the StoreInstallMethod
        $instance = $session.CreateInstance($namespaceName, $newInstance)
        $result = $session.InvokeMethod($namespaceName, $instance, "StoreInstallMethod", $params)
    }
    catch [Exception] {
        Write-Log -MessageType 'ERROR' -Message $_
    } 
    finally {
        Write-Log -MessageType 'INFO' -Message "StoreInstallMethod has been triggered"
    }

    Remove-CimSession -CimSession $session
}