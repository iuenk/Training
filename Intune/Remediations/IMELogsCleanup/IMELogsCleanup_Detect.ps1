#=============================================================================================================================
# Script Name:     IMELogsCleanup_Detect.ps1
# Description:     Detect script of Proactive Remediation script to clean up IME logs.
#
# Notes      :     Script to clean up IME logs older than 30 days, excluding specific prefixes.
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

function Get-FilesSkippingPrefixes {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LiteralPath')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string[]]$ExcludedPrefixes = @(
            'IntuneManagementExtension',
            'AgentExecutor',
            'AppActionProcessor',
            'AppWorkload',
            'ClientCertCheck',
            'ClientHealth',
            'DeviceHealthMonitoring',
            'HealthScripts',
            'Sensor',
            'Win32AppInventory'
        ),

        [int]$Depth = [int]::MaxValue,

        [switch]$IncludeHidden
    )

    begin {
        # Build the regex once per invocation
        if ($ExcludedPrefixes.Count -gt 0) {
            $escaped = $ExcludedPrefixes |
                ForEach-Object { [Regex]::Escape($_) } |
                Where-Object { $_ -ne '' }

            if ($escaped.Count -gt 0) {
                $script:PrefixRegex = '^(?:' + ($escaped -join '|') + ')'
            } else {
                $script:PrefixRegex = $null
            }
        } else {
            $script:PrefixRegex = $null
        }

        function Test-StartsWithExcludedPrefix {
            param([Parameter(Mandatory)][string]$BaseName)
            if (-not $script:PrefixRegex) { return $false }
            return [System.Text.RegularExpressions.Regex]::IsMatch($BaseName, $script:PrefixRegex, 'IgnoreCase')
        }
    }

    process {
        # Resolve the input path safely
        try {
            $resolved = Resolve-Path -Path $Path -ErrorAction Stop
            $root = $resolved.ProviderPath
        } catch {
            Write-Error "Path '$Path' could not be resolved: $($_.Exception.Message)"
            return
        }

        # Build Get-ChildItem parameters
        $gciParams = @{
            LiteralPath = $root
            File        = $true
            Recurse     = $true
            Force       = [bool]$IncludeHidden
            ErrorAction = 'SilentlyContinue'
        }
        if ($Depth -ne [int]::MaxValue -and $Depth -ge 0) {
            # PowerShell 7+: -Depth is honored; Windows PowerShell: ignored (harmless)
            $gciParams['Depth'] = $Depth
        }

        Get-ChildItem @gciParams |
            Where-Object {
                -not (Test-StartsWithExcludedPrefix -BaseName $_.BaseName)
            } |
            Select-Object @{
                    Name='FullName';       Expression = { $_.FullName }
                }, @{
                    Name='LengthBytes';    Expression = { $_.Length }
                }, @{
                    Name='SizeMB';         Expression = { [math]::Round($_.Length / 1MB, 3) }
                }, @{
                    Name='CreationTime';   Expression = { $_.CreationTime }
                }, @{
                    Name='LastWriteTime';  Expression = { $_.LastWriteTime }
                }
    }
}

$Listlogs = Get-FilesSkippingPrefixes -Path "$env:Programdata\Microsoft\IntuneManagementExtension\Logs"

$OldLogs = $Listlogs | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-30)} |Select-Object Fullname, LastWriteTime
$CountofOldLogs = ($OldLogs.Fullname | Measure-Object).Count

If($CountofOldLogs -ge 1)
{
  Write-host "There are $($CountofOldLogs) logs to be removed"  
Exit 1
}
else {
    Write-host "There are no old logs to be removed"
    Exit 0
}