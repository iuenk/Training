#=============================================================================================================================
# Script Name:     BlockRecoveryCMD_Detect.ps1
# Description:     Administrative permissions on CMD in Recovery mode are hidden
#   
# Notes      :     Administrative permissions on CMD in Recovery mode are hidden 
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$MountDirectory = 'C:\$Mount-WinRE'
$OldMountDirectory = 'C:\MountWinRE'
$CheckDirectory = 'C:\$Check-WinRE'
$OldCheckDirectory = 'C:\CheckWinRE'
$MountCheckPaths=@($MountDirectory,$OldMountDirectory)
$ApCheckPaths=@($CheckDirectory,$OldCheckDirectory)
#[string]$LogDirectory = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs"

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
	#$ReAgentcLocation = $ReAgentcInfo.split("`n")[4].Substring(31, $ReAgentcInfo.split("`n")[4].length - 31).trim()
	if ($ReAgentcStatus -eq 'Enabled') {
		Write-Log -Message "Recovery Agent is enabled, local lanquage ReAgentc status = $ReAgentcStatus"; return $true
	} else {
		Write-Log -Message "Recovery Agent is disabled, local lanquage ReAgentc status = $ReAgentcStatus"; return $false
	}
}
function Get-WinREPartitionNumber {
	Write-Log -Message "Retrieving current active WinRE partition from ReAgentc /Info"
	$ReAgentcInfo = "$Env:WinDir\System32\ReAgentc.exe /Info"|Invoke-Expression
	#$ReAgentcStatus = $ReAgentcInfo.split("`n")[3].split(' ')[-1]
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
{   # Check if there still is a mounted winre.wim to the directories used with this remediation
    if ((Test-Path $MountDirectory) -or (Test-Path $OldMountDirectory)) {
        Write-Log -Message "The path $MountCheckPaths already exist, making sure nothing is mounted." -Severity 1
        $MountedImages=Get-WindowsImage -Mounted
        if ($MountedImages) {
            foreach ($MountedImage in $MountedImages) {
                if ($MountedImage.Path -in $MountCheckPaths) {
                    Write-Log -Message "Mounted images found, triggering remediation" -Severity 1
                    Exit 1
                }
            }
        } else {
            Write-Log -Message "None of the paths $MountCheckPaths are mounted, removing the directories." -Severity 1
            Remove-Item -Recurse $MountCheckPaths -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log -Message "None of the paths $MountCheckPaths exist, continuing." -Severity 1
    }
    
    # Check if there still is an accesspath to the directories used with this remediation
    if ((Test-Path $CheckDirectory) -or (Test-Path $OldCheckDirectory)) {
		Write-Log -Message "One of the paths $APCheckPaths already exist, making sure there is no accesspath active." -Severity 1
		$AccessPaths=(Get-Partition -DiskNumber $Harddisk -PartitionNumber $Partition).AccessPaths
        if ($AccessPaths) {
            foreach ($AccessPath in $AccessPaths) {
                if (($AccessPath -like "$($CheckDirectory)\") -or ($AccessPath -like "$($OldCheckDirectory)\")) {
                    Write-Log -Message "$AccessPath Directory already exists - verifying its empty"
                    $CheckDirectoryNotEmpty = Get-ChildItem $AccessPath -Hidden
                    if ($CheckDirectoryNotEmpty) {
                        Write-Log -Message "$AccessPath directory is not empty - removing AccessPath and deleting folder"
                        Remove-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $AccessPath
                    }
                    Remove-Item $AccessPath -Force
                }
            }
        } else {
            Write-Log -Message "None of the paths $APCheckPaths are mounted, removing the directories." -Severity 1
            Remove-Item -Recurse $APCheckPaths -Force -ErrorAction SilentlyContinue
        }
	} else {
		Write-Log -Message "None of the paths $APCheckPaths exist, continuing." -Severity 1
	}
	    
	if (-not(Get-WinREStatus)) {
		Write-Log -Message 'Windows Recovery Agent not Active, trying to enable it'
        if (-not(Enable-WinRE)) {
			Write-Log -Message 'Recovery Partition cannot be enabled, cannot apply fix' -Severity 3
			exit 0
		}
	}
	
    [string]$Harddisk, [string]$Partition = (Get-WinREPartitionNumber)
	if ($Partition -gt 0) {
        
        $Folder = New-Item $CheckDirectory -ItemType Directory -Force
		$Folder.Attributes=$Folder.Attributes -bor [System.IO.FileAttributes]::Hidden
		
        Write-Log -Message "Add PartitionAccessPath to partition $Partition and accesspath $CheckDirectory"
        try {
            Add-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $CheckDirectory -ErrorAction Stop
        }
        catch {
            Write-Log -Message "Failed to add partition access path to partition $Partition and accesspath $CheckDirectory : $_" -Severity 3
        }
		$Result = Test-Path "$CheckDirectory\Recovery\WindowsRE\Fix.tag"
        Write-Log -Message "Remove PartitionAccessPath from partittion $Partition and accesspath $CheckDirectory"
        try {
            Remove-PartitionAccessPath -DiskNumber $Harddisk -PartitionNumber $Partition -AccessPath $CheckDirectory
        }
        catch {
            Write-Log -Message "Failed to remove partition access path to partition $Partition and accesspath $CheckDirectory : $_" -Severity 3
        }
        
		Write-Log -Message "Remove directory $CheckDirectory"
		Remove-Item -Path $CheckDirectory -Force

		if (-not($Result)) {
			Write-Log -Message "Fix not found"
			exit 1
		}
		Write-Log -Message "Fix found"
		exit 0
	}
	Write-Log -Message "WinRE partition is not active" -Severity 3
	exit 0
}
catch {
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 0
}