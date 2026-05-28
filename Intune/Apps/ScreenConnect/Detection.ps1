$regpath = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
if (-not ([IntPtr]::Size -eq 4)) {
    $regpath += "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
}
$propertyNames = 'DisplayName', 'DisplayVersion', 'Publisher', 'UninstallString'
$app = Get-ItemProperty $regpath -Name $propertyNames -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like "ScreenConnect*"}

if ($null -ne $app){
    Write-Output "0"
}