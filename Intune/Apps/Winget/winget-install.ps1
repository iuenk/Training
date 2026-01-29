<#
.SYNOPSIS
Install apps with Winget through Intune.
Can be used standalone.

.DESCRIPTION
Allow to run Winget in System Context to install your apps.

.PARAMETER AppIDs
Forward Winget App ID to install. For multiple apps, separate with ",". Case sensitive.

.PARAMETER Uninstall
To uninstall app. Works with AppIDs

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -Uninstall

.EXAMPLE
.\winget-install.ps1 -AppIDs "7zip.7zip -v 22.00", "Notepad++.Notepad++"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, ParameterSetName = "AppIDs")] [String[]] $AppIDs,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall
)

#region functions

# Get WinGet location
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

# Configure prefered scope option as Machine
function Add-ScopeMachine {
    #Get Settings path for system or current user
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $SettingsPath = "$Env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\defaultState\settings.json"
    }
    else {
        $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }

    $ConfigFile = @{}

    #Check if setting file exist, if not create it
    if (Test-Path $SettingsPath) {
        $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }
    else {
        New-Item -Path $SettingsPath -Force | Out-Null
    }

    if ($ConfigFile.installBehavior.preferences) {
        Add-Member -InputObject $ConfigFile.installBehavior.preferences -MemberType NoteProperty -Name 'scope' -Value 'Machine' -Force
    }
    else {
        $Scope = New-Object PSObject -Property $(@{scope = 'Machine' })
        $Preference = New-Object PSObject -Property $(@{preferences = $Scope })
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force
    }

    $ConfigFile | ConvertTo-Json | Out-File $SettingsPath -Encoding utf8 -Force
}

function Install-Prerequisites {

    Write-Host "Checking prerequisites..."

    #Check if Visual C++ 2019 or 2022 installed
    $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
    $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
    $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022 }

    #If not installed, download and install
    if (!($path)){
        Write-Host "Microsoft Visual C++ 2015-2022 is not installed."

        try {
            #Get proc architecture
            if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
                $OSArch = "arm64"
            }
            elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
                $OSArch = "x64"
            }
            else {
                $OSArch = "x86"
            }

            #Download and install
            $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
            $Installer = "$env:TEMP\VC_redist.$OSArch.exe"

            Write-Host "Downloading [$SourceURL]..."
            Invoke-WebRequest $SourceURL -UseBasicParsing -OutFile $Installer

            Write-Host "Installing VC_redist.$OSArch.exe..."
            Start-Process -FilePath $Installer -Args "/passive /norestart" -Wait
            Start-Sleep 3

            Remove-Item $Installer -ErrorAction Ignore
            Write-Host "MS Visual C++ 2015-2022 installed successfully."
        }
        catch {
            Write-Host "MS Visual C++ 2015-2022 installation failed."
        }
    }

    #Check if Microsoft.VCLibs.140.00.UWPDesktop is installed
    if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers)){
        Write-Host "Microsoft.VCLibs.140.00.UWPDesktop is not installed"
        $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $VCLibsFile = "$env:TEMP\Microsoft.VCLibs.x64.14.00.Desktop.appx"
        
        Write-Host "Downloading [$VCLibsUrl]..."
        Invoke-RestMethod -Uri $VCLibsUrl -OutFile $VCLibsFile

        try {
            Write-Host "Installing Microsoft.VCLibs.140.00.UWPDesktop..."
            Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense | Out-Null
            Write-Host "Microsoft.VCLibs.140.00.UWPDesktop installed successfully."
        }
        catch {
            Write-Host "Failed to install Microsoft.VCLibs.140.00.UWPDesktop."
        }
        Remove-Item -Path $VCLibsFile -Force
    }

    #Check available WinGet version, if fail set version to the latest version as of 2024-04-29
    $WingetURL = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    try {
        $WinGetAvailableVersion = ((Invoke-WebRequest $WingetURL -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
    }
    catch {
        $WinGetAvailableVersion = "1.7.11132"
    }

    #Get installed Winget version
    try {
        $WingetInstalledVersionCmd = & $Winget -v
        $WinGetInstalledVersion = (($WingetInstalledVersionCmd).Replace("-preview", "")).Replace("v", "")
        Write-Host "Installed Winget version: $WingetInstalledVersionCmd"
    }
    catch {
        Write-Host "WinGet is not installed" "Red"
    }

    #Check if the available WinGet is newer than the installed
    if ($WinGetAvailableVersion -gt $WinGetInstalledVersion) {

        Write-Host "Downloading Winget v$WinGetAvailableVersion"
        $WingetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WingetInstaller = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-RestMethod -Uri $WingetURL -OutFile $WingetInstaller
        
        try {
            Write-Host "Installing Winget v$WinGetAvailableVersion"
            Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
            Write-Host "Winget installed."
        }
        catch {
            Write-Host "Failed to install Winget!"
        }
        Remove-Item -Path $WingetInstaller -Force
    }

    Write-Host "Checking prerequisites ended."
}

# Check if app is installed
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

# Check if app exists
function Confirm-Exist ($AppID) {
    # Check if app exists in winget github repo
    $WingetApp = & $winget search --Id "$AppID" -e --accept-source-agreements | Out-String

    # Return if AppID exists
    if ($WingetApp -match [regex]::Escape($AppID)) {
        Write-Host "[$AppID] exists."
        return $true
    }
    else {
        Write-Host "[$AppID] does not exist! Check spelling."
        return $false
    }
}

# Install function
function Install-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID

    if (!($IsInstalled)){
        # Install App
        Write-Host "[$AppID] installing..."

        if ($AppArgs){
            Write-Host "[$AppID] using custom arguments: [$AppArgs]."
            $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -h $AppArgs" -split " "
        }
        else {
            $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -h" -split " "
        }

        Write-Host "Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Where-Object {$_ -notlike "   *"}

        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if ($IsInstalled){
            Write-Host "[$AppID] successfully installed."
        }
        else {
            Write-Host "[$AppID] installation failed!"
        }
    }
    else {
        Write-Host "[$AppID] is already installed."
    }
}

#Uninstall function
function Uninstall-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID

    if ($IsInstalled){
        #Uninstall App
        Write-Host "Uninstalling [$AppID]..."
        $WingetArgs = "uninstall --id $AppID -e --accept-source-agreements -h" -split " "

        Write-Host "Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Where-Object { $_ -notlike "   *" }

        #Check if uninstall is ok
        $IsInstalled = Confirm-Install $AppID
        if (!($IsInstalled)){
            Write-Host "[$AppID] successfully uninstalled."
        }
        else {
            Write-Host "[$AppID] uninstall failed!"
        }
    }
    else {
        Write-Host "[$AppID] is not installed."
    }
}
#endregion functions

#region main

# If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}

# Start Logging
$FileSuffix = Get-Date -format "yyyyMMdd-HHmmss"
Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget_Install_Apps_$FileSuffix.log" -Append

#Config console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

#Check if current process is elevated (System or admin user)
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$Script:IsElevated = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#Log file
$FileSuffix = Get-Date -format "yyyyMMdd-HHmmss"

#Log Header
if ($Uninstall){
    Write-Host "$(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL REQUEST"
}
else {
    Write-Host "$(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW INSTALL REQUEST"
}

#Get Winget command
$Script:Winget = Get-WingetCmd

if ($IsElevated -eq $True) {
    Write-Host "Running with admin rights."
    Install-Prerequisites

    # Reload Winget command
    $Script:Winget = Get-WingetCmd
    # Run Scope Machine funtion
    Add-ScopeMachine
}
else {
    Write-Host "Running without admin rights."
}

if ($Winget){
    #Run install or uninstall for all apps
    foreach ($App_Full in $AppIDs){
        #Split AppID and Custom arguments
        $AppID, $AppArgs = ($App_Full.Trim().Split(" ", 2))

        Write-Host "[$AppID] start processing..."

        # Install or Uninstall command
        if ($Uninstall){
            Uninstall-App $AppID $AppArgs
        }
        else {
            # Check if app exists on Winget Repo
            $Exists = Confirm-Exist $AppID
            if ($Exists){
                Install-App $AppID $AppArgs
            }
        }

        Write-Host "[$AppID] processing finished!"
        Start-Sleep 1
    }
}

Write-Host "END REQUEST"
Start-Sleep 3

Stop-Transcript
#endregion main