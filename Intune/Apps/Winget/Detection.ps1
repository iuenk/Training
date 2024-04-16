#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
if ($ResolveWingetPath){
        $WingetPath = $ResolveWingetPath[-1].Path
}

$config
Set-Location -Path $wingetpath

foreach ($PackageName in $PackageNames){
    $InstalledApp = .\winget.exe list --id $PackageName

    if ($InstalledApp -eq $PackageName) {
        Write-Host "$($PackageName) is installed"
    }
    else {
        Write-Host "$($PackageName) not detected"
        $NotDetected =+ 1
    }
}

if (!$NotDetected){
    Exit 0
} else {Exit 1}