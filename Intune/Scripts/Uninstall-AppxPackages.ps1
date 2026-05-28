#=============================================================================================================================
# Script Name:     Uninstall-AppxPackages.ps1
# Description:     This script will uninstall specified Appx packages
#   
# Notes      :     Uninstall specified Appx packages that are provisioned in the image. 
#                  This is used to remove unwanted applications from the image and prevent them from being reinstalled for new users. 
#                  The script will also remove the packages for existing users.
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$ScriptName = 'Uninstall-AppxPackages'
$LogFile = $env:ProgramData + '\Microsoft\IntuneManagementExtension\Logs\' + $ScriptName + '.log'

#region Functions

#region Write-Log
Function Write-Log {
	param(
	$MessageType, 
	$Message
	)
		$MyDate = "[{0:dd/MM/yyyy} {0:HH:mm:ss}]" -f (Get-Date)  
		Add-Content $LogFile  "$MyDate - $MessageType : $Message"  
}
#endregion
#region Uninstall-AppxPackage
Function Uninstall-AppxPackage{
	param(
	$AppxName
	)

    Write-Log -MessageType "INFO" -Message "[$AppxName]"
    Try {
	    $Package = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq $AppxName}

	    If ([string]::IsNullOrEmpty($Package)) {
		    Write-Log -MessageType "INFO" -Message "Application [$AppxName] not found."
            Write-Log -MessageType "INFO" -Message "================================================"
	    } Else {
		    Write-Log -MessageType "INFO" -Message "Found application: $($Package.DisplayName), Version: $($Package.Version), PackageName: Version: $($Package.PackageName)"
		    Write-Log -MessageType "INFO" -Message 'Executing [Remove-AppxProvisionedPackage] command.'
		    $Package | Remove-AppxProvisionedPackage -Online -AllUsers
            Write-Log -MessageType "INFO" -Message 'Executing [Remove-AppxPackage] command.'
		    Get-AppxPackage -AllUsers -Name $AppxName | Remove-AppxPackage 

		    #Check if app is uninstalled
		    $IsInstalled = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq $AppxName}
		    If ([string]::IsNullOrEmpty($IsInstalled)) { 
			    Write-Log -MessageType "INFO" -Message "Application [$($Package)] have been uninstalled successfully"
		    } Else {
			    Write-Log -MessageType "Warning" -Message "Application [$($Package)] was not successfully uninstalled"
		    }
            Write-Log -MessageType "INFO" -Message "================================================"   
	    }
    } 
    Catch {
	    Write-Log -MessageType "ERROR" -Message ""An error occured: $_""
	    Write-Host "An error occured: $_"
    }
}
#endregion

Uninstall-AppxPackage -AppxName 'Microsoft.OutlookForWindows'
Uninstall-AppxPackage -AppxName 'microsoft.windowscommunicationsapps'
Uninstall-AppxPackage -AppxName 'MicrosoftTeams'
Uninstall-AppxPackage -AppxName 'Microsoft.Office.OneNote'
Uninstall-AppxPackage -AppxName 'Microsoft.MicrosoftSolitaireCollection'