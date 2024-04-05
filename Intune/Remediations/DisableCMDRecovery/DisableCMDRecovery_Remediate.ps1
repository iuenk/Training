#=============================================================================================================================
# Script Name:     DisableCMDRecovery_Remediate.ps1
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

[System.IO.DirectoryInfo]$MountDirectory = "C:\MountWinRE"
[System.IO.DirectoryInfo]$LogDirectory = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
[String]$PKGName = "Remediate_DisableCMDRecovery"

$Script:DateTime = Get-Date -Format yyyyMMdd_HHmmss

function Write-Log {
	param (
		[parameter(Mandatory=$true, HelpMessage="Message to write to the log file.")]
		[ValidateNotNullOrEmpty()]
        [string]$Message,
         
		[parameter(Mandatory=$false, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateSet("1", "2", "3")]
        [string]$Severity="1"
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
function Disable-WinRE {
	$ReAgentcLogFile = "$LogDirectory\$($PkgName)_ReAgentc_$($Script:DateTime).log"
    $DisableRE = "$Env:WinDir\System32\ReAgentc.exe /Disable /Logpath $ReAgentcLogFile"|Invoke-Expression
    #Regex will check if the message contains an error number. Errors will cause reagentc to throw and not return anything
    #Exitcode 2 = Already disabled
    if ($LASTEXITCODE -eq 2 -or ($LASTEXITCODE -eq 0 -and ($DisableRE) -and ($DisableRE[0] -notmatch ".*\d+.*"))) {
        Write-Log -Message 'Disabled WinRE'
        return $true
    } else {
        Write-Log -Message 'Disabling failed' -Severity 2
        return $false
    }
}
function Enable-WinRE {
	$ReAgentcLogFile = "$LogDirectory\$($PkgName)_ReAgentc_$($Script:DateTime).log"
    $EnableRE = "$Env:WinDir\System32\ReAgentc.exe /Enable /Logpath $ReAgentcLogFile"|Invoke-Expression
	if ($LASTEXITCODE -eq 0) {
		if ($EnableRE[0] -notmatch ".*\d+.*") {
			Write-Log -Message 'ReAgentc Enabled WinRE'
			return $true
		}
    } else {
        Write-Log -Message 'ReAgentc Enabling WinRE failed' -Severity 2
        return $false
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
function Mount-WinRE {
	$WindowsImageLogFile = "$LogDirectory\$($PkgName)_WindowsImage_$($Script:DateTime).log"
    if (-not(Test-Path $MountDirectory)) {
        New-Item $MountDirectory -ItemType Directory -Force | Out-Null
    } else {
        Write-Log -Message 'Directory already exists - verifying its empty'
        $MountDirectoryEmpty = Get-ChildItem $MountDirectory 
        if ($MountDirectoryEmpty) {
            Write-Log -Message 'Mount directory is not empty - check if the recovery partition is already mounted'
			$REMountedStatus = $(((Get-WindowsImage -Mounted).MountStatus -eq "Ok") -and ((Get-WindowsImage -Mounted).MountDirectory -eq $MountDirectory))
			if (-not($REMountedStatus)) {
				Write-Log -Message "Mounted WinRE status is $REMountedStatus and must be remounted"
				$UnmountDiscard = Dismount-WinRE -Discard
				if (-not(Test-Path $MountDirectory)) {
					New-Item $MountDirectory -ItemType Directory -Force | Out-Null
				}
			} else {
			Write-Log -Message "Mounted WinRE status is $REMountedStatus"
			}
	    }
    }
	#Hide Mount Directory for users
	$MountDirectory.Attributes=$MountDirectory.Attributes -bor [System.IO.FileAttributes]::Hidden
	
	[string]$ActiveRecoveryHarddiskNumber,[string]$ActiveRecoveryPartitionNumber = (Get-WinREPartitionNumber)
    if ($ActiveRecoveryPartitionNumber -gt 0) {
		Write-Log -Message 'Mounting WinRE'
		$Mount = Mount-WindowsImage -Path $MountDirectory -ImagePath "\\?\GLOBALROOT\device\harddisk$ActiveRecoveryHarddiskNumber\partition$ActiveRecoveryPartitionNumber\Recovery\WindowsRE\WinRE.wim" -Index 1 -Logpath $WindowsImageLogFile
		if ($Mount) {
			if ($Mount[0] -notmatch ".*\d+.*" -and (Get-WindowsImage -Mounted).count -ge 1 -and $LASTEXITCODE -eq 0) {
				Write-Log -Message 'WinRE successfully mounted'
				return $true
			}
		} else {
			Write-Log -Message "Could not mount WinRE image - please consult the log: $($Mount)" -Severity 2
			return $false
		}
	}
}
function Dismount-WinRE {
    param(
        [switch]$Discard
    )
    $WindowsImageLogFile = "$LogDirectory\$($PkgName)_WindowsImage_$($Script:DateTime).log"
    $DismLogFile = "$LogDirectory\$($PkgName)_DISM_$($Script:DateTime).log"
    
    $REMountedStatus = $((Get-WindowsImage -Mounted).MountStatus -eq "Ok")
    if ($REMountedStatus -and -not($Discard)) {
        Write-Log -Message "Mounted WinRE status is $REMountedStatus"
        $UnmountCommit = Dismount-WindowsImage -Path $MountDirectory -Save -Logpath $WindowsImageLogFile
    } else {
        $UnmountCommit = $false
    }
    if (-not($UnmountCommit) -or $LASTEXITCODE -ne 0) {
        Write-Log -Message 'Committing failed or discarding changes on request'
        Write-Log -Message "Status of the WinRE during this operation according to Get-WindowsImage was: $((Get-WindowsImage -Mounted).MountStatus)"
        
		$UnmountDiscard = Dismount-WindowsImage -Path $MountDirectory -discard -Logpath $WindowsImageLogFile
        if ($LASTEXITCODE -ne 0) {
            if ($(Get-WindowsImage -Mounted).count -ge 1) {
                Write-Log -Message 'Unmounting failed, please consult the logs' -Severity 2
                return $false
            } 
        } else {
            Write-Log -Message 'Unmounting done, discarded changes'
        }   
    } elseif ($UnmountCommit[0] -notmatch ".*\d+.*") {
        Write-Log -Message 'WinRE committed changes successfully'
    }
	Remove-Item $MountDirectory -Force -Recurse
    return $true
}

try
{
	if (-not(Get-WinREStatus)) {
		Write-Log -Message 'Windows Recovery Agent not Active, trying to enable it' -Severity 2
		if (-not(Enable-WinRE)) {
			Write-Log -Message 'Error Enabling the Recovery Partition' -Severity 3
			exit 1
		}
	}
    #Mount WinRE image
	Write-Log -Message 'Mount WinRE'
	if (-not(Mount-WinRE)) {
		Write-Log -Message 'Error Mounting WinRE image' -Severity 3
		Exit 1
	}
	
	# Change ACL for cmd.exe, continue if not found	
	if (-not(Test-Path "$MountDirectory\Windows\System32\cmd.exe")) {
		Write-Log -Message 'cmd.exe not found, WinRE image is already modified'
		$UnmountDiscard = Dismount-WinRE -Discard
		if ($UnmountDiscard) {
			Write-Log -Message 'Mounted WinRE image successfully unmounted.'
		} else {
			Write-Log -Message 'Error Unmounting WinRE image. Please check logs' -Severity 3
			Exit 1
		}
	} else {
		$NewAcl = Get-Acl -Path "$MountDirectory\Windows\System32\cmd.exe" -ErrorAction Continue
		$Identity = "SYSTEM"
		$FileSystemRights = "FullControl"
		$Type = "Allow"
		$FileSystemAccessRuleArgumentList = $Identity, $FileSystemRights, $Type
		$FileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $FileSystemAccessRuleArgumentList
		$NewAcl.SetAccessRule($FileSystemAccessRule)
		Set-Acl -Path "$MountDirectory\Windows\System32\cmd.exe" -AclObject $NewAcl -ErrorAction Continue
		Rename-Item "$MountDirectory\Windows\System32\cmd.exe" -NewName "cmd.old" -Force -ErrorAction Continue
    
		$UnmountCommit = Dismount-WinRE
		if ($UnmountCommit) {
			Write-Log -Message 'Mounted WinRE image successfully committed and unmounted.'
		} else {
			Write-Log -Message 'Error Unmounting WinRE image. Please check logs' -Severity 3
			Exit 1
		}
	}
	
    #Tag the recovery partition to show it has the fix applied
	[string]$ActiveRecoveryHarddiskNumber,[string]$ActiveRecoveryPartitionNumber = (Get-WinREPartitionNumber)
	Write-Log -Message 'Add TAG to Windows RE Image.'
	$DetectPath = "C:\CheckWinRE"
	if (-not(Test-Path $DetectPath)) {
        $Folder = New-Item $DetectPath -ItemType Directory -Force
    } else {
	    Write-Log -Message 'CheckWinRE Directory already exists - verifying its empty'
        $DetectPathEmpty = Get-ChildItem $DetectPath -Hidden
        if ($CheckPathEmpty) {
			Write-Log -Message 'CheckWinRE directory is not empty - removing possible AccessPath and deleting folder'
			$AccessPathStatus = ((Get-Volume -FilePath $DetectPath).OperationalStatus -eq 'OK')
			Remove-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $DetectPath
			Remove-Item $DetectPath -Force
			$Folder = New-Item -Path $DetectPath -ItemType Directory -Force
		} else {
			$Folder = Get-Item -Path $DetectPath -Force
		}
    }	
	$Folder.Attributes=$Folder.Attributes -bor [System.IO.FileAttributes]::Hidden
    
    Add-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $DetectPath
	if (-not(Test-Path "$DetectPath\Recovery\WindowsRE\Fix.tag")) {
		New-Item "$DetectPath\Recovery\WindowsRE\Fix.tag" -ItemType File -Force | Out-null
	}
    Remove-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $DetectPath
    Remove-Item $DetectPath -Force

    Write-Log -Message "Fix Applied"
	exit 0
}
catch{
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}