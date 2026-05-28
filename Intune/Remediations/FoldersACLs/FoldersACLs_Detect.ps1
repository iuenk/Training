#=============================================================================================================================
# Script Name:     FoldersACLs_Detect.ps1
# Description:     Detect script of Proactive Remediation script to manage folder permissions.
#
# Notes      :     Script to set permissions on: 'C:\' and 'Users\Public'
#
# Created by :     Ivo Uenk
# Date       :     15-05-2026
# Version    :     1.0
#
# Version history:
# 1.0 - Tested and finalized version, ready for production use.

#region EventID Reference Table
# =========================
# EventID Reference Table
# =========================

# Write-Log function
# 999   : Default eventID for generic log entries.

# SIDSandNTs region
# 160   : Error creating or translating SID to NTAccount.
# 161   : Error creating oddMSCapabilitySID.
# 162   : Error creating OddMSCapabilityPermissions.
# 163   : Error creating desiredCDrivePermissions.
# 164   : Error creating CFAppDRaESync or DelSubDirFilModSync permissions.
# 165   : Error creating desiredPublicPermissions.
# 166   : Error creating desiredCDSToolsPermissions.
# 167   : Error creating desiredCDSPrivatePermissions.

# CDrive region
# 168   : Error retrieving C:\ ACL.
# 169   : Error comparing C:\ ACL to desired ACL.
# 170   : C:\ permissions mismatch detected (remediation required).

# usersPublic region
# 171   : Error retrieving Users\Public ACL.
# 172   : Error comparing Users\Public ACL to desired ACL.
# 173   : Users\Public permissions mismatch detected (remediation required).

# Script completion
# 101   : Script detected issues, exiting with error.
# 100   : Script completed successfully, no issues found.
#endRegion EventID Reference Table
#=============================================================================================================================

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [String]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3)]
        [Int16]$Severity = 1,
        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [String]$Source = $([String]$parentFunctionName = [IO.Path]::GetFileNameWithoutExtension((Get-Variable -Name 'MyInvocation' -Scope 1 -ErrorAction 'SilentlyContinue').Value.MyCommand.Name); If ($parentFunctionName) {
                $parentFunctionName
            }
            Else {
                'mainScript'
            }),
        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileDirectory,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [String]$LogFileName,
        [Parameter (Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [Decimal]$MaxLogFileSizeMB,
        [Parameter (Mandatory = $false)]
        [ValidateNotNullorEmpty()]
        [Int]$MaxLogHistory,
        [Parameter(Mandatory = $false)]
        [Boolean]$AppendToLogFile = $true,
        [Parameter(Mandatory = $false)]
        [string]$EventLog,
        [Parameter(Mandatory = $false)]
        [string]$EventSource,
        [Parameter(Mandatory = $false)]
        [switch]$LogEventLog = $false,
        [Parameter(Mandatory = $false)]
        [int]$eventID = 999
    )

    begin {
        [String]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        [DateTime]$DateTimeNow = Get-Date
        [String]$LogTime = $DateTimeNow.ToString('HH\:mm\:ss.fff')
        [String]$LogDate = $DateTimeNow.ToString('MM-dd-yyyy')
        If (-not (Test-Path -LiteralPath 'variable:LogTimeZoneBias')) {
            [Int32]$script:LogTimeZoneBias = [TimeZone]::CurrentTimeZone.GetUtcOffset($DateTimeNow).TotalMinutes
        }
        [String]$LogTimePlusBias = $LogTime + $script:LogTimeZoneBias

        [ScriptBlock]$CMTraceLogString = {
            Param (
                [String]$lMessage,
                [String]$lSource,
                [Int16]$lSeverity
            )
                "<![LOG[$lMessage]LOG]!>" + "<time=`"$LogTimePlusBias`" " + "date=`"$LogDate`" " + "component=`"$lSource`" " + "context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " + "type=`"$lSeverity`" " + "thread=`"$PID`" " + "file=`"$ScriptSource`">"
            }

        ## Assemble the fully qualified path to the log file
        [String]$LogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $LogFileName

        # check for Log Size & Rotate if needed
        if (Test-Path -Path $LogFilePath -PathType Leaf) {
            Try {
                $LogFile = Get-Item $LogFilePath
                [Decimal]$LogFileSizeMB = $LogFile.Length / 1MB

                # Check if log file needs to be rotated
                if ((!$script:LogFileInitialized) -and ($MaxLogFileSizeMB -gt 0 -and $LogFileSizeMB -gt $MaxLogFileSizeMB)) {

                    # Get new log file path
                    $LogFileNameWithoutExtension = [IO.Path]::GetFileNameWithoutExtension($LogFileName)
                    $LogFileExtension = [IO.Path]::GetExtension($LogFileName)
                    $Timestamp = $LogFile.LastWriteTime.ToString('yyyy-MM-dd-HH-mm-ss')
                    $ArchiveLogFileName = "{0}_{1}{2}" -f $LogFileNameWithoutExtension, $Timestamp, $LogFileExtension
                    [String]$ArchiveLogFilePath = Join-Path -Path $LogFileDirectory -ChildPath $ArchiveLogFileName

                    if ($LogFileSizeMB -gt $MaxLogFileSizeMB) {
                        [Hashtable]$ArchiveLogParams = @{Source = ${CmdletName}; Severity = 2; LogFileDirectory = $LogFileDirectory; LogFileName = $LogFileName;MaxLogFileSizeMB = 0; AppendToLogFile = $true; EventLog = $EventLog; EventSource = $EventSource}

                        ## Log message about archiving the log file
                        $ArchiveLogMessage = "Maximum log file size [$MaxLogFileSizeMB MB] reached. Rename log file to [$ArchiveLogFileName]."
                        Write-Log -Message $ArchiveLogMessage @ArchiveLogParams
                    }

                    # Rename the file
                    Move-Item -Path $LogFilePath -Destination $ArchiveLogFilePath -Force -ErrorAction 'Stop'

                    if ($MaxLogFileSizeMB -gt 0 -and $LogFileSizeMB -gt $MaxLogFileSizeMB) {
                        ## Start new log file and Log message about archiving the old log file
                        $NewLogMessage = "Previous log file was renamed to [$ArchiveLogFileName] because maximum log file size of [$MaxLogFileSizeMB MB] was reached."
                        Write-Log -Message $NewLogMessage @ArchiveLogParams
                    }

                    # Get all log files (including any .lo_ files that may have been created by previous toolkit versions) sorted by last write time
                    $LogFiles = @(Get-ChildItem -LiteralPath $LogFileDirectory -Filter ("{0}_*{1}" -f $LogFileNameWithoutExtension, $LogFileExtension)) + @(Get-Item -LiteralPath ([IO.Path]::ChangeExtension($LogFilePath, 'lo_')) -ErrorAction Ignore) | Sort-Object LastWriteTime

                    # Keep only the max number of log files
                    if ($LogFiles.Count -gt $MaxLogHistory) {
                        $LogFiles | Select-Object -First ($LogFiles.Count - $MaxLogHistory) | Remove-Item -ErrorAction 'Stop'
                    }
                }
            }
            Catch {
                Write-Host -Object "[$LogDate $LogTime] [${CmdletName}] $ScriptSection :: Failed to rotate the log file [$LogFilePath]. `r`n$(Resolve-Error)" -ForegroundColor 'Red'
                # Treat log rotation errors as non-terminating by default
                If (-not $ContinueOnError) {
                    Return
                }
            }
        }

        # Check if event log and source exist
        If ($script:logFileInitialized -eq $false ) {
            If ([System.Diagnostics.EventLog]::Exists($EventLog) -eq $false) {New-EventLog -LogName $EventLog -Source $EventSource}
            If ([System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $false) {
                New-EventLog -LogName $EventLog -Source $EventSource
            }
        }
    $script:LogFileInitialized = $true

    } Process {

        [String]$CMTraceLogLine = & $CMTraceLogString -lSource $Source -lSeverity $Severity -lMessage $message 
        $CMTraceLogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'

        If ($severity -eq 3) {
            $errorMessage = @()
            $errorMessage += "Message: $($Error[0].Exception.Message)"
            $errorMessage += "Exception Type: $($Error[0].Exception.GetType().FullName)"
            $errorMessage += "FullyQualifiedErrorId: $($Error[0].FullyQualifiedErrorId)"
            $errorMessage += "CategoryInfo: $($Error[0].CategoryInfo)"
            $errorMessage += "Command: $($Error[0].InvocationInfo.MyCommand)"
            $errorMessage += "Line Number: $($Error[0].InvocationInfo.ScriptLineNumber)"
            [string]$errorMessageString = $errorMessage -join "`n"
            [String]$CMTraceLogLine = & $CMTraceLogString -lSource $Source -lSeverity $Severity -lMessage $errorMessageString
            $CMTraceLogLine | Out-File -FilePath $LogFilePath -Append -NoClobber -Force -Encoding 'UTF8' -ErrorAction 'Stop'
        }
        
        If ($LogEventLog -eq $true) {
            switch ($severity) {
                0 {$entryType = 'Information'}
                1 {$entryType = 'Information'}
                2 {$entryType = 'Warning'}
                3 {$entryType = 'Error'}
                Default {$entryType = 'Information'}
            }
            Write-EventLog -Logname $EventLog -Source $EventSource -EntryType $entryType -EventId $eventID -Message $Message
            If ($entryType -eq 'Error') {
                Write-EventLog -Logname $EventLog -Source $EventSource -EntryType $entryType -EventId $eventID -Message $errorMessageString
            }
        }
    }
}

function Compare-AccessControlList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [array]$CurrentAccessRules,
        [Parameter(Mandatory = $false)]
        [array]$DesiredAccessRules
    )
    begin {    }
    process {
        $hasIssue = $false
        $additionalRules = @()
        $missingRules = @()

        # Check if all current rules are in the desired ACL
        foreach ($currentRule in $CurrentAccessRules) {
            # If no ACL is provided, any current rule is considered an issue (as they were not in the ignore list)
            If (-not $DesiredAccessRules) {
                $hasIssue = $true
                $additionalRules += $currentRule
            } else {
                # Check if the current rule exists in the desired ACLs
                $existsInDesired = $false
                foreach ($rule in $DesiredAccessRules) {
                    if (
                        $currentRule.IdentityReference -eq $rule.IdentityReference -and
                        $currentRule.FileSystemRights -eq $rule.FileSystemRights -and
                        $currentRule.InheritanceFlags -eq $rule.InheritanceFlags -and
                        $currentRule.PropagationFlags -eq $rule.PropagationFlags -and
                        $currentRule.AccessControlType -eq $rule.AccessControlType
                    ) {
                        $existsInDesired = $true
                        break
                    }
                }
                if (-not $existsInDesired) {
                    $hasIssue = $true
                    $additionalRules += $currentRule
                }
            }
        }

        If ($DesiredAccessRules) {
            # Also check the other way around: if there are rules in the ACL that are not in the current rules, they are considered missing
            foreach ($rule in $DesiredAccessRules) {
                # If no current rules are provided, any desired rule is considered missing
                If (-not $CurrentAccessRules) {
                    $hasIssue = $true
                    $missingRules += $rule
                } else {
                    $existsInCurrent = $false
                    foreach ($currentRule in $CurrentAccessRules) {
                        # If the rule is not in the current rules, it is considered missing
                        if (
                            $rule.IdentityReference -eq $currentRule.IdentityReference -and
                            $rule.FileSystemRights -eq $currentRule.FileSystemRights -and
                            $rule.InheritanceFlags -eq $currentRule.InheritanceFlags -and
                            $rule.PropagationFlags -eq $currentRule.PropagationFlags -and
                            $rule.AccessControlType -eq $currentRule.AccessControlType
                        ) {
                            $existsInCurrent = $true
                            break
                        }
                    }
                    If (-not $existsInCurrent) {
                            $hasIssue = $true
                            $missingRules += $rule
                    }
                }
            }
        }
        
        return [PSCustomObject]@{
            hasIssue = $hasIssue
            additionalRules = $additionalRules
            missingRules = $missingRules
        }
    }
}
#endRegion Functions

#region Variables
#region LoggingVariables
$logFileDirectory = $env:ProgramData + "\Microsoft\IntuneManagementExtension\Logs"
$logFileName = "WEN-FoldersACLs.log"
$maxLogFileSizeMB = 2
$maxLogHistory = 2
$eventLog = "WEN_CMW"
$eventSource = "WEN-FoldersACLs"
$generalLogParams = @{
    LogFileDirectory = $logFileDirectory
    LogFileName = $logFileName
    MaxLogFileSizeMB = $maxLogFileSizeMB
    MaxLogHistory = $maxLogHistory
    EventLog = $eventLog
    EventSource = $eventSource
}
$script:LogFileInitialized = $false
$ContinueOnError = $false
$writeHost = $false
$logType = "CMTrace"
$ScriptSection = 'mainScript'
$PassThru = $false

If ($MyInvocation.MyCommand.Path) {
    $scriptSource = $MyInvocation.MyCommand.Path
} else {
    $scriptSource = "cmdline"
}
#endRegion LoggingVariables
$sysDrive = $env:SystemDrive +'\'
$publicPath = "$env:SystemDrive\Users\Public"
$permissionIssue = $false
$ErrorActionPreference = 'Stop'
# Define SIDs for well-known accounts and translate to NTAccount names to account for OS language localization
$SIDObjects = @(
    @{ Name = 'systemSID'; SID = "S-1-5-18"; NTVar = 'systemNT' },
    @{ Name = 'adminsSID'; SID = "S-1-5-32-544"; NTVar = 'adminsNT' },
    @{ Name = 'batchSID'; SID = "S-1-5-3"; NTVar = 'batchNT' },
    @{ Name = 'serviceSID'; SID = "S-1-5-6"; NTVar = 'serviceNT' },
    @{ Name = 'UsersSID'; SID = "S-1-5-32-545"; NTVar = 'UsersNT' },
    @{ Name = 'authenticatedUsersSID'; SID = "S-1-5-11"; NTVar = 'authenticatedUsersNT' },
    @{ Name = 'creatorOwnerSID'; SID = "S-1-3-0"; NTVar = 'creatorOwnerNT' }
)
# NOTE for future versions:
# When retrieving permissions under System for anything under Program Files or Windows, permissions are often returned as 32-bit integers to provide Permissions for App Installers.
# These are not enumerable FileSystemRights, but rather a combination of FileSystemRights and AccessMask Bitmask values. This makes it harder to manage permissions integrally.
# If you want to handle these permissions, you need to translate these integers to Rights, without using .net FileSystemRights enumeration.
# For more info, read: https://stackoverflow.com/questions/28029872/retrieving-security-descriptor-and-getting-number-for-filesystemrights
#endRegion Variables

#region SIDSandNTs
Write-Log @generalLogParams -Message "===================== Starting DETECTION script for Folders and Permissions ====================="

Write-Log @generalLogParams -Message "Defining SIDs and NTAccount names for well-known accounts."
foreach ($sidObj in $SIDObjects) {
    try {
        Set-Variable -Name $sidObj.Name -Value (New-Object System.Security.Principal.SecurityIdentifier($sidObj.SID))
        Set-Variable -Name $sidObj.NTVar -Value ((Get-Variable -Name $sidObj.Name).Value.Translate([System.Security.Principal.NTAccount]))
    } catch {
        Write-Log @generalLogParams -Message "Error creating or translating $($sidObj.Name) with SID $($sidObj.SID)." -Severity 3 -LogEventLog -eventID 160
    }
}

# On my C:\ at time of writing, the below SID had the permissions "ReadData, ExecuteFile, ReadAttributes, Synchronize". Unknown what this is for, but it seems to refer to a capability SID that is used by a Microsoft Store App.
# See more info here https://www.reddit.com/r/CMMC/comments/1g9xdst/any_official_ms_documentation_for_sid/
# As it is also included on clean installs of Windows. I include it.
try {
    $oddMSCapabilitySID = New-Object System.Security.Principal.SecurityIdentifier("S-1-15-3-65536-1888954469-739942743-1668119174-2468466756-4239452838-1296943325-355587736-700089176")
} catch {
    Write-Log @generalLogParams -Message "Error creating oddMSCapabilitySID." -Severity 3 -LogEventLog -eventID 161
}

Write-Log @generalLogParams -Message "Finished creating SIDs and NTAccount names for well-known accounts."
Write-Log @generalLogParams -Message "Continuing to create Permission definitions."

# Define permissions object, with bit operator, for the oddMSCapabilitySID.
try {
    $OddMSCapabilityPermissions = [System.Security.AccessControl.FileSystemRights]::ReadData -bor [System.Security.AccessControl.FileSystemRights]::ExecuteFile `
    -bor [System.Security.AccessControl.FileSystemRights]::ReadAttributes -bor [System.Security.AccessControl.FileSystemRights]::Synchronize
} catch {
    Write-Log -Message "Error creating OddMSCapabilityPermissions." @generalLogParams -Severity 3 -LogEventLog -eventID 162
}

# Define desired permissions for the C:\ drive
try {
    $desiredCDrivePermissions = @()
    $desiredCDrivePermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($systemNT, 'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $desiredCDrivePermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($adminsNT, 'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $desiredCDrivePermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($UsersNT, 'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
    $desiredCDrivePermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($oddMSCapabilitySID, $OddMSCapabilityPermissions,'None','None','Allow')
} catch {
    Write-Log @generalLogParams -Message "Error creating desiredCDrivePermissions." -Severity 3 -LogEventLog -eventID 163
}


#Define the desired ACL's for the C:\Users\Public Folder.
try {
    $CFAppDRaESync = [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor [System.Security.AccessControl.FileSystemRights]::AppendData `
        -bor [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Synchronize

    $DelSubDirFilModSync = [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [System.Security.AccessControl.FileSystemRights]::Modify `
        -bor [System.Security.AccessControl.FileSystemRights]::Synchronize
} catch {
    Write-Log @generalLogParams -Message "Error creating CFAppDRaESync or DelSubDirFilModSync permissions." -Severity 3 -LogEventLog -eventID 164
}

# Define the desired ACL's for the C:\Users\Public folder.
try {
    $desiredPublicPermissions = @()
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($creatorOwnerNT, 'FullControl','ContainerInherit,ObjectInherit','InheritOnly','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($batchNT, $CFAppDRaESync,'None','None','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($batchNT, $DelSubDirFilModSync,'ContainerInherit,ObjectInherit','InheritOnly','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($serviceNT, $CFAppDRaESync,'None','None','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($serviceNT, $DelSubDirFilModSync,'ContainerInherit,ObjectInherit','InheritOnly','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($systemNT, 'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($adminsNT, 'FullControl','ContainerInherit,ObjectInherit','None',"Allow")
    $desiredPublicPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($UsersNT, 'ReadAndExecute','ContainerInherit,ObjectInherit','None',"Allow")     
} catch {
    Write-Log @generalLogParams -Message "Error creating desiredPublicPermissions." -Severity 3 -LogEventLog -eventID 165
}
 
# Define the desired ACL's for the C:\Program Files\CEDS Tools folder.
try {
    $desiredCDSToolsPermissions = @()
    $desiredCDSToolsPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($systemNT, 'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $desiredCDSToolsPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($adminsNT, 'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
    $desiredCDSToolsPermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($UsersNT, 'ReadAndExecute','ContainerInherit,ObjectInherit','None',"Allow")
} catch {
    Write-Log @generalLogParams -Message "Error creating desiredCDSToolsPermissions." -Severity 3 -LogEventLog -eventID 166
}

# Define the desired ACL's for the C:\Program Files\CEDS Tools\Private folder.
try {
    $desiredCDSPrivatePermissions = @()
    $desiredCDSPrivatePermissions += New-Object System.Security.AccessControl.FileSystemAccessRule($systemNT, 'FullControl','ContainerInherit,ObjectInherit','None','Allow')    
} catch {
    Write-Log @generalLogParams -Message "Error creating desiredCDSPrivatePermissions." -Severity 3 -LogEventLog -eventID 167
}
#endRegion SIDSandNTs
#endregion Variables

Write-Log @generalLogParams -Message "Finished creating Permission definitions. Continuing to check folders."

#region CDrive
try {
    $cACL = Get-ACL -Path $sysDrive
} catch {
    Write-Log @generalLogParams -Message "Error retrieving '$sysDrive' ACL." -Severity 3 -LogEventLog -eventID 168
}

try {
    $cCheck = Compare-AccessControlList -CurrentAccessRules $cACL.Access -DesiredAccessRules $desiredCDrivePermissions
} catch {
    Write-Log @generalLogParams -Message "Error Comparing '$sysDrive' ACL to Desired ACL." -Severity 3 -LogEventLog -eventID 169
}

If ($cCheck.hasIssue) {
    $message = "'$sysDrive' permissions do not match the desired state. Remediation required."
    If ($cCheck.additionalRules.Count -gt 0) {
        $message += "`nAdditional rules found:" + ($cCheck.additionalRules | ForEach-Object {
            "`nIdentityReference: $($_.IdentityReference); FileSystemRights: $($_.FileSystemRights); InheritanceFlags: $($_.InheritanceFlags); PropagationFlags: $($_.PropagationFlags); AccessControlType: $($_.AccessControlType)"
        })
    }
    If ($cCheck.missingRules.Count -gt 0) {
        $message += "`nMissing rules:" + ($cCheck.missingRules | ForEach-Object {
            "`nIdentityReference: $($_.IdentityReference); FileSystemRights: $($_.FileSystemRights); InheritanceFlags: $($_.InheritanceFlags); PropagationFlags: $($_.PropagationFlags); AccessControlType: $($_.AccessControlType)"
        })
    }
    Write-Log @generalLogParams -Message $message -Severity 2 -LogEventLog -eventID 170
    # To be reverted if we want to remediate Cdrive
    #$permissionIssue = $true
} else {
    Write-Log @generalLogParams -Message "'$sysDrive' permissions match the desired state."
}
#endRegion CDrive

#region usersPublic
try {
    $publicACL = Get-Acl -Path $publicPath
} catch {
    Write-Log @generalLogParams -Message "Error retrieving '$publicPath' ACL." -Severity 3 -LogEventLog -eventID 171
}

try {
    $publicCheck = Compare-AccessControlList -CurrentAccessRules $publicACL.Access -DesiredAccessRules $desiredPublicPermissions
} catch {
    Write-Log @generalLogParams -Message "Error Comparing '$publicPath' ACL to Desired ACL." -Severity 3 -LogEventLog -eventID 172
}

If ($publicCheck.hasIssue) {
    # To be reverted if we want to remediate CUsersPublic
    #$permissionIssue = $true
    $message = "'$publicPath' permissions do not match the desired state. Remediation required."
    If ($publicCheck.additionalRules.Count -gt 0) {
        $message += "`nAdditional rules found:" + ($publicCheck.additionalRules | ForEach-Object {
            "`nIdentityReference: $($_.IdentityReference); FileSystemRights: $($_.FileSystemRights); InheritanceFlags: $($_.InheritanceFlags); PropagationFlags: $($_.PropagationFlags); AccessControlType: $($_.AccessControlType)"
        })
    }
    If ($publicCheck.missingRules.Count -gt 0) {
        $message += "`nMissing rules:" + ($publicCheck.missingRules | ForEach-Object {
            "`nIdentityReference: $($_.IdentityReference); FileSystemRights: $($_.FileSystemRights); InheritanceFlags: $($_.InheritanceFlags); PropagationFlags: $($_.PropagationFlags); AccessControlType: $($_.AccessControlType)"
        })
    }
    Write-Log @generalLogParams -Message $message -Severity 2 -LogEventLog -eventID 173
} else {
    Write-Log @generalLogParams -Message "'$publicPath' folder permissions match the desired state."
}
#endRegion usersPublic

If ($permissionIssue) {
    Write-Log @generalLogParams -Message "Issues Detected. Exit 1" -Severity 2 -LogEventLog -eventID 101
    Write-Host "Issues Detected. Exit 1"
    exit 1
} else {
    Write-Log @generalLogParams -Message "No issues found with folders or permissions." -Severity 1 -LogEventLog -eventID 100
    Write-Host "No issues found with folders or permissions."
    exit 0
}