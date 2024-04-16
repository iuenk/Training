# Put ID as PackageName
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')
$FileSuffix = Get-Date -format "yyyyMMdd-HHmmss"

$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller

# Start Logging
Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Install_Apps_$FileSuffix.log" -Append

# Check if Winget needs to be installed
If($AppInstaller.Version -lt "2022.506.16.0") {
    Write-Host "Winget is not installed, trying to install latest version from Github"

    Try {        
        Write-Host "Creating Winget Packages Folder"

        if (!(Test-Path -Path C:\ProgramData\WinGetPackages)) {
            New-Item -Path C:\ProgramData\WinGetPackages -Force -ItemType Directory
        }

        Set-Location C:\ProgramData\WinGetPackages

        #Downloading Packagefiles
        #Microsoft.UI.Xaml.2.7.0
        Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.7.0" -OutFile "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.2.7.0.zip"
        Expand-Archive C:\ProgramData\WinGetPackages\microsoft.ui.xaml.2.7.0.zip -Force
        #Microsoft.VCLibs.140.00.UWPDesktop
        Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile "C:\ProgramData\WinGetPackages\Microsoft.VCLibs.x64.14.00.Desktop.appx"
        #Winget
        Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "C:\ProgramData\WinGetPackages\Winget.msixbundle"
        #Installing dependencies + Winget
        Add-ProvisionedAppxPackage -online -PackagePath:.\Winget.msixbundle -DependencyPackagePath .\Microsoft.VCLibs.x64.14.00.Desktop.appx,.\microsoft.ui.xaml.2.7.0\tools\AppX\x64\Release\Microsoft.UI.Xaml.2.7.Appx -SkipLicense

        Write-Host "Starting sleep for Winget to initiate"
        Start-Sleep 2
    }
    Catch {
        Throw "Failed to install Winget"
        Break
    }

}
Else {
    Write-Host "Winget already installed, moving on"
}

$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
if ($ResolveWingetPath){
        $WingetPath = $ResolveWingetPath[-1].Path
}

$config
Set-Location -Path $wingetpath

# #Trying to install Package with Winget
if ($null -ne $PackageNames){
    foreach ($PackageName in $PackageNames){
        try {
            Write-Host "Installing $($PackageName) via Winget"
            .\winget.exe install $PackageName --silent --accept-source-agreements --accept-package-agreements
        }
        catch {
            Throw "Failed to install package $($_)"
        }
    }
}
else {
    Write-Host "No packages found"
}
Stop-Transcript