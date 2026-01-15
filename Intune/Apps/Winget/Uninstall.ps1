#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

#Start Logging
Start-Transcript -Path "C:\C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Uninstall_Apps_$FileSuffix.log" -Append

#Detect Apps
foreach ($PackageName in $PackageNames){
    $AppFound = ((winget list --id $PackageName)[-1]).split(" ")

    if ($PackageName -in $AppFound) {    
        Write-Host "Trying to uninstall $($PackageName)"
        try {        
            winget uninstall $PackageName --silent
        }
        catch {
            Throw "Failed to uninstall $($PackageName)"
        }
    }
    else {
        Write-Host "$($PackageName) is not installed or detected"
    }
}

Stop-Transcript