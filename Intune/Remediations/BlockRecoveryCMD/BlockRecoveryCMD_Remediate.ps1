#=============================================================================================================================
# Script Name:     BlockRecoveryCMD_Remediate.ps1
# Description:     Administrative permissions on CMD in Recovery mode are hidden
#   
# Notes      :     Administrative permissions on CMD in Recovery mode are hidden 
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#=============================================================================================================================

$PkgName='Remediate_DisableCMDRecovery'
$MountDirectory = 'C:\$Mount-WinRE'
$OldMountDirectory = 'C:\MountWinRE'
$CheckDirectory = 'C:\$Check-WinRE'
$OldCheckDirectory = 'C:\CheckWinRE'
$LogDirectory = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs"

$MountCheckPaths=@($MountDirectory,$OldMountDirectory)
$ApCheckPaths=@($CheckDirectory,$OldCheckDirectory)

$Script:DateTime = Get-Date -Format yyyyMMdd_HHmmss

Function Write-Log {
    param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyCollection()]
        [Alias('Text')]
        [String[]]$Message,
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateRange(1, 3)]
        [Int16]$Severity = 1,
		[Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNull()]
        [String]$Source = $([String]$parentFunctionName = [IO.Path]::GetFileNameWithoutExtension((Get-Variable -Name 'MyInvocation' -Scope 1 -ErrorAction 'SilentlyContinue').Value.MyCommand.Name); If ($parentFunctionName) {
                $parentFunctionName
            }
            Else {
                'Unknown'
            }),
		[Parameter(Mandatory = $false, Position = 3)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileDirectory = "$Env:ProgramData\Microsoft\IntuneManagementExtension\Logs",
		[Parameter(Mandatory = $false, Position = 4)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileName = "$PkgName.log"
    )
	[DateTime]$DateTimeNow = Get-Date
    [String]$LogTime = $DateTimeNow.ToString('HH\:mm\:ss.ffffff')
    [String]$LogDate = $DateTimeNow.ToString('MM-dd-yyyy')
	try {
        If ($script:MyInvocation.Value.ScriptName) {
            [String]$ScriptSource = Split-Path -Path $script:MyInvocation.Value.ScriptName -Leaf -ErrorAction 'Stop'
        } Else {
            [String]$ScriptSource = Split-Path -Path $script:MyInvocation.MyCommand.signature -Leaf -ErrorAction 'Stop'
        }
    }
    catch {
        $ScriptSource = ''
    }
    $CMTraceMessage = "<![LOG[$Message]LOG]!>" + "<time=`"$LogTime`" " + "date=`"$LogDate`" " + "component=`"$Source`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$Severity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
	## Assemble the fully qualified path to the log file
    [String]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName
    $CMTraceMessage | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
	Switch ($Severity) {
		3 {
			Write-Host -Object $Message -ForegroundColor 'Red'
        }
        2 {
			Write-Host -Object $Message -ForegroundColor 'Yellow'
        }
        1 {
			Write-Host -Object $Message
        }
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
function Mount-WinRE {
	$WindowsImageLogFile = "$LogDirectory\$($PkgName)_WindowsImage_$($Script:DateTime).log"
    if (-not(Test-Path $MountDirectory)) {
        $Folder = New-Item $MountDirectory -ItemType Directory -Force
    } else {
        Write-Log -Message 'Directory already exists - verifying its empty'
        $MountDirectoryEmpty = Get-ChildItem $MountDirectory 
        if ($MountDirectoryEmpty) {
            Write-Log -Message 'Mount directory is not empty - check if the recovery partition is already mounted'
			$REMountedStatus = $(((Get-WindowsImage -Mounted).MountStatus -eq "Ok") -and ((Get-WindowsImage -Mounted).MountPath -eq $MountDirectory))
			if (-not($REMountedStatus)) {
				Write-Log -Message "Mounted WinRE status is $REMountedStatus and must be remounted"
				$UnmountDiscard = Dismount-WinRE -Discard
				if (-not(Test-Path $MountDirectory)) {
					$Folder = New-Item $MountDirectory -ItemType Directory -Force
				}
			} else {
			Write-Log -Message "Mounted WinRE status is $REMountedStatus"
			}
	    } else {
			$Folder = $MountDirectory
		}

    }
	#Hide Mount Directory for users
	$Folder.Attributes=$Folder.Attributes -bor [System.IO.FileAttributes]::Hidden
	
	[string]$ActiveRecoveryHarddiskNumber,[string]$ActiveRecoveryPartitionNumber = (Get-WinREPartitionNumber)
    if (($ActiveRecoveryPartitionNumber -gt 0) -and (-not($REMountedStatus))) {
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
	} else {
		## WINRE is already mounted and oprational status is OK
		return $true
	}
}
function Dismount-WinRE {
    param(
        [switch]$Discard
    )
    $WindowsImageLogFile = "$LogDirectory\$($PkgName)_WindowsImage_$($Script:DateTime).log"
    #$DismLogFile = "$LogDirectory\$($PkgName)_DISM_$($Script:DateTime).log"
    
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

try {
    Write-Log -Message 'Checking if the Winre.wim file is mounted to one of the paths'
    if ((Test-Path $MountDirectory) -or (Test-Path $OldMountDirectory)) {
		Write-Log -Message "One of the paths $MountCheckpaths already exists, making sure nothing is mounted." -Severity 1
		$MountedImages=Get-WindowsImage -Mounted 
        if ($MountedImages) {  ##Mounted Images found
            foreach ($MountedImage in $MountedImages) {
                if ($MountedImage.Path -in $MountCheckPaths) {
                    try {
                        Write-Log -Message "Attempting to dismount $($MountedImage.Path) directory" -Severity 1
                        Dismount-WindowsImage -Path $MountedImage.Path -Discard -ErrorAction Continue
                        Write-Log -Message "Attempting to remove $($MountedImage.Path) directory" -Severity 1
                        Remove-Item -Recurse $($MountedImage.Path) -Force
                    }
                    catch {
                        Write-Log -Message "Error dismounting Windows image on mountpoint $($MountedImage.Path): $_" -Severity 3
                        exit 1
                    }
                }
            }
        } else {
            Write-Log -Message "None of the paths $MountCheckPaths are mounted, removing the directories." -Severity 1
            Remove-Item -Recurse $MountCheckPaths -Force -ErrorAction SilentlyContinue
        }
	} else {
		Write-Log -Message "None of the paths $MountCheckpaths exist, checking if nobody else has the winre.wim mounted (Update-WinRE)" -Severity 1
        [int32]$Timeout=0
        $Status=$true
        do {
            $MountedImages=Get-WindowsImage -Mounted
            if ($MountedImages) {
                foreach ($MountedImage in $MountedImages) {
                    if ($MountedImage.ImagePath -like '*WinRE.wim*') {
                        Write-Log -Message "WinRE.wim is mounted on mountpoint $($MountedImage.Path) to image path $($MountedImage.ImagePath), delaying script for 5 minutes"
                        $Status=$false
                        $Timeout++
                        Start-Sleep -Seconds 5
                    } else {
                        $Status=$true
                    }
                }
            } else {
                $Status=$true
            }
        } Until ($Status -or $Timeout -eq 12)
        if ($Timeout -eq 12) {
            Write-Log -Message 'Time-out waiting for dismount of the WinRE.wim file' -Severity 3
            exit 1
        }
    }
	
    # Check if there still is an accesspath to the directories used with this remediation
    if ((Test-Path $CheckDirectory) -or (Test-Path $OldCheckDirectory)) {
		Write-Log -Message "One of the paths $APCheckPaths already exist, making sure there is no accesspath active." -Severity 1
        [string]$ActiveRecoveryHarddiskNumber,[string]$ActiveRecoveryPartitionNumber = (Get-WinREPartitionNumber)
		$AccessPaths=(Get-Partition -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber).AccessPaths
        if ($AccessPaths) {
            foreach ($AccessPath in $AccessPaths) {
                if (($AccessPath -like "$($CheckDirectory)\") -or ($AccessPath -like "$($OldCheckDirectory)\")) {
                    Write-Log -Message "$AccessPath Directory already exists - verifying its empty"
                    $CheckDirectoryNotEmpty = Get-ChildItem $AccessPath -Hidden
                    if ($CheckDirectoryNotEmpty) {
                        Write-Log -Message "$AccessPath directory is not empty - removing AccessPath and deleting folder"
                        Remove-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $AccessPath
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
        Write-Log -Message "SetACl on $MountDirectory\Windows\System32\cmd.exe."
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
	
    $Folder = New-Item $CheckDirectory -ItemType Directory -Force
    $Folder.Attributes=$Folder.Attributes -bor [System.IO.FileAttributes]::Hidden
	
    try {
        Add-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $CheckDirectory
    }
    catch {
        Write-Log -Message "Failed to add partition access path to partition $ActiveRecoveryPartitionNumbern and accesspath $CheckDirectory : $_" -Severity 3
        exit 1
    }
	if (-not(Test-Path "$CheckDirectory\Recovery\WindowsRE\Fix.tag")) {
		New-Item "$CheckDirectory\Recovery\WindowsRE\Fix.tag" -ItemType File -Force | Out-null
	}
    try {
        Remove-PartitionAccessPath -DiskNumber $ActiveRecoveryHarddiskNumber -PartitionNumber $ActiveRecoveryPartitionNumber -AccessPath $CheckDirectory
    }
    catch {
        Write-Log -Message "Failed to remove partition access path to partition $Partition and accesspath $CheckDirectory : $_" -Severity 3
    }
    Remove-Item $CheckDirectory -Force

    Write-Log -Message "Fix Applied"
	exit 0
}
catch{
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}