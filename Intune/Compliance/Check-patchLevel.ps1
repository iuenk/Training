<#
Version: 1.0
Author: Ivo Uenk
Script: Check-patchLevel
Description: Check patch level
#> 

$patchLevel = $false

# Get OS build info from current device
$ProductName = (Get-CimInstance Win32_OperatingSystem).Caption
$CurrentBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuild).CurrentBuild
$UBR = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR
$OSVersion = $CurrentBuild + "." + $UBR

# The update list will be retrieved from Microsoft https://support.microsoft.com/en-us/rss-feed-picker
if($ProductName -like "*10*"){$uList = 'https://support.microsoft.com/en-us/feed/atom/6ae59d69-36fc-8e4d-23dd-631d98bf74a9'}
if($ProductName -like "*11*"){$uList = 'https://support.microsoft.com/en-us/feed/atom/4ec863cc-2ecd-e187-6cb3-b50c6545db92'}

# Fix for Invoke-WebRequest creating BOM in XML files; Handle Temp locations on Windows, macOS / Linux
try {
    if(Test-Path env:Temp){$tempDir = $env:Temp}
    elseif(Test-Path env:TMPDIR){$tempDir = $env:TMPDIR}

    $tempFile = Join-Path -Path $tempDir -ChildPath ([System.IO.Path]::GetRandomFileName())
    Invoke-WebRequest -Uri $uList -ContentType 'application/atom+xml; charset=utf-8' -UseBasicParsing -OutFile $tempFile

    # Import the XML from the feed into a variable and delete the temp file
    $xml = [xml](Get-Content -Path $tempFile -raw)
    Remove-Item -Path $tempFile

    # Get latest update and update that match OSVersion exclude Out-of-band and Preview updates
    $cPatch = ($xml.feed.entry.title | Where-Object {$_.'#text' -match $OSVersion}).'#text' | Select-Object -First 1
    $lPatch = ($xml.feed.entry.title | Where-Object {$_.'#text' -match $OSVersion.Split('.')[0] -and $_.'#text' -notmatch "Out-of-band" -and $_.'#text' -notmatch "Preview"}).'#text' | Select-Object -First 1

    # Beware for special characters in xml
    $cDate = [DateTime]($cPatch -replace '[^\p{L}\p{Nd}/(/)/}/,/ ]', '-').Split('-', 2)[0] 
    $lDate = [DateTime]($lPatch -replace '[^\p{L}\p{Nd}/(/)/}/,/ ]', '-').Split('-', 2)[0] 

    # Try to get managed setting on device to determine when Quality updates must be installed (can only be found when managed with WufB).
    $DeferQualityUpdatesPeriodInDays = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update).DeferQualityUpdatesPeriodInDays
    $ConfigureDeadlineForQualityUpdates = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update).ConfigureDeadlineForQualityUpdates

    # Check difference between last released Quality update and the current installed Quality update minus Quality defer period and deadline
    $days = (New-TimeSpan -Start $cDate -End $lDate).Days - $DeferQualityUpdatesPeriodInDays - $ConfigureDeadlineForQualityUpdates

    # When difference equals or is less than 30 days it's true
    # False will result in non-compliance state
    if($days -le "90"){$patchLevel = $true} 
    else {$patchLevel = $false}

    $output = @{
        patchLevel = $patchLevel
    }
    return $output | convertTo-Json -Compress
} 
catch {
    # When URL cannot be contacted the compliance state will be compliant for this check
    Remove-Item -Path $tempFile -ErrorAction SilentlyContinue

    $patchLevel = $true
    $output = @{
        patchLevel = $patchLevel
    }
    return $output | convertTo-Json -Compress
}