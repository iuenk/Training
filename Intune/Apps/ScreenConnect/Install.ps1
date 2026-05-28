# Install ScreenConnect
$proc = Start-Process -Filepath "msiexec.exe" -ArgumentList "/i ScreenConnect.ClientSetup.msi", "/qn /norestart" -Wait -PassThru -NoNewWindow -ErrorAction Stop

if ($proc.ExitCode -eq 0) {
    Write-Output "0"
} else {
    Write-Output "1"
}