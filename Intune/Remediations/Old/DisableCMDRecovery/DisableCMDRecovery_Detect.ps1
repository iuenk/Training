#=============================================================================================================================
# Script Name:     DisableCMDRecovery_Detect.ps1
# Description:     Detect if Administrative permissions on CMD in Recovery mode are hidden
#   
# Notes      :     Script created (Version as received from Marco Sap (Microsoft). Note: No MS Support, Warranty or Responsibility provided)
#				   Added additional logging and rewrite of script to enhanced script error handling
#				   Added validation on partition number to prevent accesspath errors
#				   Added ErrorAction statement to prevent termination of the script, added path for reagentc execution and changed WinRe status check to prevent language mismatch
#				   Fix for partitionumber finding. Rewriten string extraction to regular expression to prevent OS language differences errors
#
# Created by :     Ivo Uenk
# Date       :     14-3-2023
# Version    :     1.0
#=============================================================================================================================

[System.IO.DirectoryInfo]$CheckPath = "C:\CheckWinRE"
[System.IO.DirectoryInfo]$LogDirectory = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
[String]$PKGName = "Detect_DisableCMDRecovery"

$Script:DateTime = Get-Date -Format yyyyMMdd_HHmmss

function Write-Log {
	param (
		[parameter(Mandatory=$true, HelpMessage="Message to write to the log file.")]
		[ValidateNotNullOrEmpty()]
        [string]$Message,
         
		[parameter(Mandatory=$false, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateSet("1", "2", "3")]
        [string]$Severity=1
	)
    
	$Message = $PKGName + ": " + $Message
	try {
        # Write either verbose or warning output to console
        switch ($Severity) {
            1 {
                Write-Host $Message -Foregroundcolor Green
            }
			2 {
				Write-Host $Message -Foregroundcolor Yellow
            }
			3 {
				Write-Error $Message
			}
            default {
                Write-Host $Message -Foregroundcolor Green
            }
        }
    }
	catch [System.Exception] {
		Write-Error -Message "Unable to write to the log. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
	}
}
function Get-WinREStatus {
    Write-Log -Message 'Retrieving current WinRE status from ReAgentc /Info'
    $ReAgentcInfo = "$Env:WinDir\System32\ReAgentc.exe /Info"|Invoke-Expression
    $ReAgentcStatus = $ReAgentcInfo.split("`n")[3].split(' ')[-1]
	$ReAgentcLocation = $ReAgentcInfo.split("`n")[4].Substring(31, $ReAgentcInfo.split("`n")[4].length - 31).trim()
	if ($ReAgentcLocation) {
		Write-Log -Message "Recovery Agent is enabled, local lanquage ReAgentc status = $ReAgentcStatus"; return $true
	} else {
		Write-Log -Message "Recovery Agent is disabled, local lanquage ReAgentc status = $ReAgentcStatus"; return $false
	}
}
function Get-WinREPartitionNumber {
	Write-Log -Message "Retrieving current active WinRE partition from ReAgentc /Info"
	$ReAgentcInfo = "$Env:WinDir\System32\ReAgentc.exe /Info"|Invoke-Expression
	$ReAgentcStatus = $ReAgentcInfo.split("`n")[3].split(' ')[-1]
	[string]$ReAgentcLocation = $ReAgentcInfo -match '\\\\\?\\GLOBALROOT\\device'
	if ($ReAgentcLocation -match '\\\\\?\\GLOBALROOT\\device\\harddisk(?<harddisknumber>.+)\\partition(?<partitionnumber>.+)\\Recovery\\WindowsRE') {
		[string]$Location = $Matches[0]
		Write-Log -Message "Recovery Agent is enabled, WinRE location = $Location"
		return $Matches.harddisknumber, $Matches.partitionnumber
	} else {
		Write-Log -Message "Recovery Agent is disabled"
		return 0,0
	}
}
function Enable-WinRE {
	$EnableRE = "$Env:WinDir\System32\ReAgentc.exe /Enable"|Invoke-Expression
	if ($LASTEXITCODE -eq 0) {
		if ($EnableRE[0] -notmatch ".*\d+.*") {
			Write-Log -Message 'ReAgentc Enabled WinRE'
			return $true
		}
    } else {
        Write-Log -Message 'ReAgentc Enabling failed' -Severity 2
        return $false
    }
}
try
{
	if (-not(Get-WinREStatus)) {
		Write-Log -Message 'Windows Recovery Agent not Active, trying to enable it'
		if (-not(Enable-WinRE)) {
			Write-Log -Message 'Error Enabling the Recovery Partition' -Severity 3
			exit 1
		}
	}
	
    [string]$Harddisk, [string]$Partition = (Get-WinREPartitionNumber)
	if ($Partition -gt 0) {
		if (-not(Test-Path $CheckPath)) {
			$Folder = New-Item $CheckPath -ItemType Directory -Force
		} else {
			Write-Log -Message 'CheckWinRE Directory already exists - verifying its empty'
			$CheckPathEmpty = Get-ChildItem $CheckPath -Hidden
			if ($CheckPathEmpty) {
				Write-Log -Message 'CheckWinRE directory is not empty - removing possible AccessPath and deleting folder'
				$AccessPathStatus = ((Get-Volume -FilePath $CheckPath).OperationalStatus -eq 'OK')
				Remove-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $CheckPath
				Remove-Item $CheckPath -Force
				$Folder = New-Item -Path $CheckPath -ItemType Directory -Force
			} else {
				$Folder = Get-Item -Path $CheckPath -Force
			}
		}
		$Folder.Attributes=$Folder.Attributes -bor [System.IO.FileAttributes]::Hidden
		
		Add-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $CheckPath
		$Result = Test-Path "$CheckPath\Recovery\WindowsRE\Fix.tag"
		Remove-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $CheckPath
		Remove-Item -Path $CheckPath -Force

		if (-not($Result)) {
			Write-Log -Message "Fix not found"
			exit 1
		}
		Write-Log -Message "Fix found"
		exit 0
	}
	Write-Log -Message "WinRE partition is not active" -Severity 3
	exit 1
}
catch{
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}