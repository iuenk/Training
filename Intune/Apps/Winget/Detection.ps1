#Fill this variable with the Winget package ID
$PackageNames = @('Adobe.Acrobat.Reader.64-bit','7zip.7zip')

foreach ($PackageName in $PackageNames){
    $AppFound = ((winget list --id $PackageName)[-1]).split(" ")

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