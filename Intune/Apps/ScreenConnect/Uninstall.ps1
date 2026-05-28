$regpath = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
if (-not ([IntPtr]::Size -eq 4)) {
    $regpath += "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
}
$propertyNames = 'DisplayName', 'DisplayVersion', 'Publisher', 'UninstallString'
$app = Get-ItemProperty $regpath -Name $propertyNames -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -like "ScreenConnect*"}

if ($null -ne $app){
    $proc = Start-Process -Filepath "msiexec.exe" -ArgumentList "/X $($app.PSChildName)", "/qn /norestart" -Wait -PassThru -NoNewWindow -ErrorAction Stop

    if ($proc.ExitCode -eq 0) {
        Write-Output "0"
    } else {
        Write-Output "1"
    }
}