#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

$winget = Get-ChildItem -Path 'C:\Program Files\WindowsApps\' -Filter winget.exe -recurse | Sort-Object -Property 'FullName' -Descending | Select-Object -First 1 -ExpandProperty FullName

foreach ($PackageName in $PackageNames){
    $AppFound = ((& "$winget" list --id $PackageName 2>&1)[-1]).split(" ")

    if ($PackageName -in $AppFound) {
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