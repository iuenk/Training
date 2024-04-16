#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

#Creating Loggin Folder
if (!(Test-Path -Path C:\ProgramData\WinGetLogs)) {
    New-Item -Path C:\ProgramData\WinGetLogs -Force -ItemType Directory
}
#Start Logging
Start-Transcript -Path "C:\C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Uninstall_Apps_$FileSuffix.log" -Append

$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
if ($ResolveWingetPath){
        $WingetPath = $ResolveWingetPath[-1].Path
}

$config
Set-Location -Path $wingetpath

#Detect Apps
foreach ($PackageName in $PackageNames){
    $InstalledApp = .\winget.exe list --id $PackageName

    if ($InstalledApp -eq $PackageName) {    
        Write-Host "Trying to uninstall $($PackageName)"
        try {        
            .\winget.exe uninstall $PackageName --silent
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