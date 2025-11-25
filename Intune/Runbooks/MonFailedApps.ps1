#=============================================================================================================================
# Script Name:     MonFailedApps.ps1
# Description:     Alert for failed Intune app installations.
#   
# Notes      :     Platform default is all OS, you can specify one or more Windows, macOS, iOS and Android.
#                  Ignore will exclude apps that contain the specified word in the displayName.
#                  The script will create an incident for every failed app that has not been resolved yet.
#
# Created by :     Ivo Uenk
# Date       :     15-04-2025
# Version    :     1.1
#=============================================================================================================================

# Variables
$Path = "$env:TEMP"
$FileSuffix = Get-Date -format "yyyyMMdd-HHmmss"
$Report = "$Path\Failed_App_Installations_Report_$FileSuffix.csv"

$tenantName = "<TenantName>"
$thresholdDays = 30
$platform = "Windows" # "Windows", "macOS", "iOS", "Android"
$ignore = "TEST_" # Ignore apps that contain this word in the displayName

Write-Output "Check apps in tenant [$tenantName] that failed to install for the last [$thresholdDays] days."

# Convert KeyVault SecureString to Plaintext
$clientId = "<clientId>"
$secret = "<secret>"
$tenantId = "<tenantId>"

try {

	$connectionDetails = @{
		'TenantId'     = $tenantId
		'ClientId'     = $clientId
		'ClientSecret' = $secret | ConvertTo-SecureString -AsPlainText -Force
	}

	# Acquire a token as demonstrated in the previous examples
	$token = Get-MsalToken @connectionDetails

	$authHeader = @{
		'Authorization' = $token.CreateAuthorizationHeader()
	}
	return $authHeader
}
Catch {
	write-host $_.Exception.Message -f Red
	write-host $_.Exception.ItemName -f Red
	write-host
	break
}

# Get all app installations
$body = @{
    top = 999
    orderBy = @("FailedDeviceCount desc")
}
$body = $body | ConvertTo-Json

$uri = "https://graph.microsoft.com/beta/deviceManagement/reports/getFailedMobileAppsReport"
$data = (Invoke-RestMethod -Uri $uri -Headers $authHeader -Body $body -ContentType "application/json")

# Convert the data to a readable table
$allApps = $data.Values | foreach-object `
-Begin {$propertyNames = @($data.Schema.Column)} `
-Process {
    $properties = [ordered] @{};
    for( $i = 0; $i -lt $data.Schema.Length; $i++ ){
        $properties[$propertyNames[$i]] = $_[$i];
    }
    new-object PSCustomObject -Property $properties
}

# Get only apps that have 1 or more failed installations
if($ignore){
    # Ignore apps that contain specific word in displayName
    Write-Output "Ignore apps that contain specific word [$ignore] in displayName."
    $allApps = $allApps | Where-Object {($_.FailedDeviceCount -ne 0) -and ($_.displayName -notlike "*$ignore*")}
}else{
    $allApps = $allApps | Where-Object {$_.FailedDeviceCount -ne 0}
}

# When failed installations are found continue
if($allApps){
    $allFailedAppEntries = @()
    $thresholdDateTime = (get-date).AddDays("-" + $thresholdDays)

    Write-Output "Configured platforms to check in tenant [$tenantName]: [$platform]."
    $platform = $platform.Split(",")

    foreach ($p in $platform){
        # Process failed apps for the specified OS
        $pApps = $allApps | Where-Object {$_.Platform_loc -eq $p}

        Write-Output "[$p] apps with failures in tenant [$tenantName]: [$($pApps.Count)]."

        # Get detailed info about what failed for every app
        foreach ($app in $pApps){
            Write-Output "[$($app.Platform_loc)] app [$($app.DisplayName)] with id [$($app.ApplicationId)] failed installations: [$($app.FailedDeviceCount)]."
            
            $body = @{filter = "(ApplicationId eq '$($app.ApplicationId)')"}
            $body = $body | ConvertTo-Json  

            $uri = "https://graph.microsoft.com/v1.0/deviceManagement/reports/microsoft.graph.retrieveDeviceAppInstallationStatusReport"
            $data = (Invoke-RestMethod -Uri $uri -Headers $authHeader -Body $body -ContentType "application/json")

            $allAppEntries = $data.Values | foreach-object `
            -Begin {$propertyNames = @($data.Schema.Column)} `
            -Process {
                $properties = [ordered] @{
                    ApplicationName = $app.DisplayName
                    ApplicationId = $_.ApplicationId
                };
                for( $i = 0; $i -lt $data.Schema.Length; $i++ ){
                    $properties[$propertyNames[$i]] = $_[$i];
                }
                new-object PSCustomObject -Property $properties
            }

            # Check if the app failed and the last modified date is within the threshold
            $allAppEntries = $allAppEntries | Where-Object {($_.AppInstallState_loc -eq "Failed") -and ($_.LastModifiedDateTime -ge $thresholdDateTime)}

            if($null -ne $allAppEntries){
                [array]$failedAppEntries = $allAppEntries | `
                Select-Object ApplicationName, ApplicationId, UserPrincipalName, Platform, DeviceName, DeviceId, LastModifiedDateTime, HexErrorCode, AppInstallStateDetails_loc
                $allFailedAppEntries += $failedAppEntries
            }
        }
    }

    #Configure Mail Properties
    Write-Output "Total [$($allFailedAppEntries.Count)] Failed app installations the last [$thresholdDays] days in tenant [$tenantName]."
    $allFailedAppEntries | Export-Csv -Path $Report -NoTypeInformation -Encoding OEM -delimiter "," 

    $Subject = "Failed app installations [$($allFailedAppEntries.Count)] the last [$thresholdDays] days in tenant [$tenantName]"
    $Body = "Automated export of all failed app installations [$($allFailedAppEntries.Count)] the last [$thresholdDays] days in tenant [$tenantName]."

    $Attachments = @(
        $Report
    )

    Write-Output "Send mail with all failed app installations the last [$thresholdDays] days in tenant [$tenantName]."
    Send-Mail -Recipients $Recipients -attachments $Attachments -Subject $Subject -Body $Body -MailSender $MailSender

    if(Test-Path -Path $Report){
        Write-output "Remove CSV file [$Report]."
        Remove-item -Path $Report
    }
}
else {
    Write-Output "No failed app installations found the last [$thresholdDays] days in tenant [$tenantName]."
}