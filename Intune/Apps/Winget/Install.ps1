Param
  (
    [parameter(Mandatory=$false)]
    [String[]]
    $param
  )

# Put ID as PackageName
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')
$FileSuffix = Get-Date -format "yyyyMMdd-HHmmss"

$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller

# Start Logging
Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Install_Apps_$FileSuffix.log" -Append

$winget_exe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe"
if ($winget_exe.count -gt 1){
        $winget_exe = $winget_exe[-1].Path
}

if (!$winget_exe){
    Write-Host "Winget is not installed trying to install latest version from Github."

    try {        
        Write-Host "Creating Winget Packages Folder."

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

        Write-Host "Starting sleep for Winget to initiate."
        Start-Sleep 2
    }
    catch {
        throw "Failed to install Winget. Error: $($_)"
        break
    }

}
else {
    Write-Host "Winget already installed Version: $($AppInstaller.Version)."
}

if ($null -ne $PackageNames){
    foreach ($PackageName in $PackageNames){
        try {
            Write-Host "Installing $($PackageName) via Winget."
            & $winget_exe install --exact --id $PackageName --silent --accept-package-agreements --accept-source-agreements --scope=machine $param
        }
        catch {
            Throw "Failed to install package. Error: $($_)"
        }
    }
}
else {
    Write-Host "No packages found"
}

Stop-Transcript