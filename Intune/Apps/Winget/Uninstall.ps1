#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

#Start Logging
Start-Transcript -Path "C:\C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Uninstall_Apps_$FileSuffix.log" -Append

$winget = Get-ChildItem -Path 'C:\Program Files\WindowsApps\' -Filter winget.exe -recurse | Sort-Object -Property 'FullName' -Descending | Select-Object -First 1 -ExpandProperty FullName

#Detect Apps
foreach ($PackageName in $PackageNames){
    $AppFound = ((& "$winget" list --id $PackageName 2>&1)[-1]).split(" ")

    if ($PackageName -in $AppFound) {    
        try {        
            Write-Host "Trying to uninstall $($PackageName) via Winget"
            Start-Process -FilePath $winget -NoNewWindow -Wait -ArgumentList "uninstall $PackageName --silent"
            Start-Sleep -Seconds 15
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