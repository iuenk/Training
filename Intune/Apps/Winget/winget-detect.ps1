# Add the AppIDs you want to detect in the array below
$AppIDs = "7zip.7zip", "Google.Chrome", "9WZDNCRFJ3PZ", "Adobe.Acrobat.Reader.64-bit"

#region functions
function Get-WingetCmd {

    $WingetCmd = $null

    #Get WinGet Path
    try {
        #Get Admin Context Winget Location
        $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        #If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo[-1].FileName
    }
    catch {
        #Get User context Winget Location
        if (Test-Path "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe") {
            $WingetCmd = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        }
    }

    return $WingetCmd
}

# Check if app exists
function Confirm-Install ($AppID) {
    # List WinGet AppID
    $InstalledApp = & $winget list --Id $AppID -e --accept-source-agreements | Out-String

    # Return if AppID exists in the list
    if ($InstalledApp -match [regex]::Escape($AppID)){
        return $true
    }
    else {
        return $false
    }
}
#endregion functions

#region main
#Get WinGet Location Function
$winget = Get-WingetCmd

if ($Winget){
    #Run install or uninstall for all apps
    foreach ($AppID in $AppIDs){
        # Check if app exists on Winget Repo
        $Exists = Confirm-Install $AppID
        if ($Exists){
            Write-Host "[$AppID] installed!"
        }
        else {
            Write-Host "[$AppID] not installed!"
            $NotDetected =+ 1
        }
    }
}

if (!$NotDetected){
    Exit 0
} else {Exit 1}
#endregion main