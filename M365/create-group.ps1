#=============================================================================================================================
#
# Script Name:     create-group.ps1
# Description:     Create security group onpremise and in the cloud, distribution group or SharePoint site (with Teams).
#   
# Notes      :     It's necessary to have the RoleManagement.ReadWrite.Directory to create security groups that 
#                  support role assignments.
#
# Created by :     Ivo Uenk
# Date       :     3-7-2024
# Version    :     1.0
#=============================================================================================================================

Param (
  [string] $CustomerId,
  [string] $DLEmail,
  [string] $GroupName,
  [string] $GroupDescription,
  [string] $Type,
  [string] $RespondersEmail,
  [boolean] $RoleAssignable,
  [boolean] $Teams,
  [boolean] $Sharing,
  [boolean] $CloudGroup,
  [boolean] $SecMailEnabled,
  [boolean] $Email
)

#. .\AppRunEnv.ps1
. .\AppMail.ps1
. .\AppAuthHeader.ps1
. .\AppTestAllowedUser.ps1
. .\AppRetryCmdlet.ps1
. .\AppWriteLog.ps1

################## Variables ##################

$File = "Aanmaken-Groep" + "-" + "$Type" + "-" + ((Get-Date).ToString("dd-MM-yyyy-HHmm"))
$FilePath = $env:TEMP + "\" + $File + ".log"
$SelfServiceGroup = Get-AutomationVariable -Name "SelfServiceGroup"

$MailSender = Get-AutomationVariable -Name "EmailAutomation"
$Recipient = $RespondersEmail
$Recipients = $Recipient.Split(",")
$RecipientCC = Get-AutomationVariable -Name "EmailSupport"
$RecipientsCC = $RecipientCC.Split(",")

$TenantName = Get-AutomationVariable -Name "TenantName"
$Language = Get-AutomationVariable -Name "DefaultLanguage"
$EmailDomain = Get-AutomationVariable -Name "EmailDomain"
$SPOReadOnlyGroup = Get-AutomationVariable -Name "SPOReadOnlyGroup"
$SharingDomain = Get-AutomationVariable -Name "SharingDomain"
$SharingDomain = $SharingDomain.Split(",")

$Server = Get-AutomationVariable -Name "OnPremDomain"
$LDAPGroupPath = Get-AutomationVariable -Name "LDAPGroupPath"

################## Functions ##################

function Add-OfficeGroup{
    [CmdletBinding()]
    param(
        [ValidateLength(1,64)]
        [Parameter(Mandatory = $true)]
        [String]$DisplayName,
        [ValidateLength(1,64)]
        [Parameter(Mandatory = $true)]
        [string]$Alias,
        [Parameter(Mandatory = $true)]
        [ValidateSet("Public", "Private")]
        [string]$AccessType ,
        [Parameter(Mandatory = $true)]
        [string]$EmailAddress,
        [Parameter(Mandatory = $true)]
        [switch]$RequireSenderAuthenticationEnabled,
        [ValidateSet("NL-NL", "EN-US", "EN-UK")]
        [Parameter(Mandatory = $true)]
        [string]$Language,
        [switch]$EnableSharing,
        [Parameter(Mandatory = $true)]
        [String]$TenantName,
        [ValidateSet("AllowFullAccess", "AllowLimitedAccess", "BlockAccess")]
        [string]$ConditionalAccessPolicy,
        [Parameter(ParameterSetName='Teams')]
        [switch]$Teams,
        [string]$SharingDomain,
        [Parameter(ParameterSetName='Teams')]
        [bool]$AllowCreateUpdateRemoveTabs = $false,
        [Parameter(ParameterSetName='Teams')]
        [bool]$AllowAddRemoveApps =$false,
        [Parameter(ParameterSetName='Teams')]
        [bool]$AllowDeleteChannels =$false,
        [Parameter(ParameterSetName='Teams')]
        [bool]$AllowCreateUpdateChannels =$false,
        [Parameter(ParameterSetName='Teams')]
        [bool]$AllowCreateUpdateRemoveConnectors =$false
    )

    process{
        # Check if SPO site can be found to determine if Microsoft365 group needs to be created
        $SPOIdentity = Get-SPOSite -Limit all | Where-Object {$_.url -like "*/sites/$Alias"}

        if($Alias.Length -gt 27){
            $ShortAlias  = $Alias.Substring(0, 27)                
        }else{
            $ShortAlias = $Alias
        }

        if(-not($SPOIdentity)){
            # Create Microsoft365 group
            try{
                New-UnifiedGroup -DisplayName "$DisplayName" `
                    -RequireSenderAuthenticationEnabled $RequireSenderAuthenticationEnabled `
                    -AccessType $AccessType `
                    -Language $Language `
                    -EmailAddresses "SMTP:$EmailAddress" `
                    -Alias $Alias | Out-Null

                Write-output "Unified groep [$DisplayName] is aangemaakt."
                Write-Log -LogOutput ("Unified groep [$DisplayName] is aangemaakt.") -Path $FilePath

                # Check if Microsoft365 group can be found
                if(!($Identity = (Get-UnifiedGroup -Identity $ShortAlias`_*))){
                    $n = 1    
                    do{
                        $Identity = (Get-UnifiedGroup -Identity $ShortAlias`_*)
                        $n++
                        Write-output ""Get-UnifiedGroup -Identity [$Alias] : 15 seconden""
                        Start-Sleep -Seconds 15
                    }until (($Identity) -or ($n -eq 10))
                }
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het aanmaken van Unified groep [$Alias] is mislukt. $_") -Path $FilePath               
                Write-Error "Het aanmaken van Unified groep [$Alias] is mislukt. $_"
            }                

            if($global:ErrorCount -eq 0){
                # Set Microsoft365 group settings
                Set-UnifiedGroup -Identity $($identity.Name) -HiddenFromAddressListsEnabled $true -ErrorAction stop | Out-Null
                Write-output "Setting HiddenFromAddressListsEnabled voor [$($identity.Name)]."
                Write-Log -LogOutput ("Setting HiddenFromAddressListsEnabled voor [$($identity.Name)].") -Path $FilePath

                Set-UnifiedGroup -Identity $($identity.Name) -UnifiedGroupWelcomeMessageEnabled:$false -ErrorAction stop | Out-Null
                Write-output "Setting UnifiedGroupWelcomeMessageEnabled voor [$($identity.Name)]."
                Write-Log -LogOutput ("Setting UnifiedGroupWelcomeMessageEnabled voor [$($identity.Name)].") -Path $FilePath

                [int]$c=1
                do{
                    try{
                        Start-Sleep -Seconds 20
                        $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$ShortAlias')"
                        $UnifiedGroup = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value

                        $Uri = "https://graph.microsoft.com/v1.0/groups/$($UnifiedGroup.id)/drive/"
                        Invoke-WebRequest -Uri $Uri -Headers $($global:authHeader) -UseBasicParsing
                        $GroupEnabled = $true
                    }catch{
                        $GroupEnabled = $false
                        $c++
                    }
                }until($GroupEnabled -or ($c -eq 10))

                if($GroupEnabled){
                    Write-output "Het configureren van unified groep [$Alias] is afgerond."
                    Write-Log -LogOutput ("Het configureren van unified groep [$Alias] is afgerond.") -Path $FilePath

                    # Wait till SPO site url is found
                    if(!($SPOIdentity = Get-SPOSite "https://$TenantName.sharepoint.com/sites/$Alias")){
                        $n = 1
                    
                        do{
                            $SPOIdentity = Get-SPOSite "https://$TenantName.sharepoint.com/sites/$Alias" -ErrorAction SilentlyContinue
                            $n++
                            Write-output "get-SPOSite https://$TenantName.sharepoint.com/sites/$Alias wachten 15 seconden"
                            Start-Sleep -Seconds 15
                        }until(($SPOIdentity) -or ($n -eq 10)) 
                    }
                }else{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het configureren van unified groep [$Alias] is mislukt.") -Path $FilePath
                    Write-error "Het configureren van unified groep [$Alias] is mislukt."
                }
            }
        }
        else{     
            Write-output "Site [$alias] bestaat al ga verder met site configuratie."
        }  

        if($global:ErrorCount -eq 0){
            try{
                if($EnableSharing){
                    Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$Alias" -SharingCapability 'ExternalUserSharingOnly' -ErrorAction Stop | Out-Null
                    Write-output "Aanzetten ExternalUserSharingOnly voor [$Alias]."
                    Write-Log -LogOutput ("Aanzetten ExternalUserSharingOnly voor [$Alias].") -Path $FilePath

                    if($SharingDomain){
                        Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$Alias" -SharingAllowedDomainList "$SharingDomain" -SharingDomainRestrictionMode 'allowlist' -ErrorAction Stop | Out-Null
                    }    
                }
                else{
                    Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$alias" -SharingCapability 'Disabled' -ErrorAction Stop | Out-Null
                    Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$alias" -DisableSharingForNonOwners:$true -ErrorAction Stop | Out-Null
                    Write-output "Uitzetten sharing capabilities voor [$Alias]."
                    Write-Log -LogOutput ("Uitzetten sharing capabilities voor [$Alias].") -Path $FilePath
                }

                if($ConditionalAccessPolicy){
                    Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$alias" -ConditionalAccessPolicy $ConditionalAccessPolicy -ErrorAction Stop | Out-Null
                    Write-output "Instellen CA Policy [$ConditionalAccessPolicy] voor [$Alias]."
                    Write-Log -LogOutput ("Instellen CA Policy [$ConditionalAccessPolicy] voor [$Alias].") -Path $FilePath
                }
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het configureren van site [$Alias] is mislukt. $_") -Path $FilePath               
                Write-Error "Het configureren van site [$Alias] is mislukt. $_"
            }
        }

        if($global:ErrorCount -eq 0){
            try{
                if($Teams){
                    # Retrieve group id when site was already found
                    if(-not($UnifiedGroup)){
                        $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$ShortAlias')"
                        $UnifiedGroup = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value
                    }

                    New-Team -Group $($UnifiedGroup.id) -ErrorAction Stop | out-null
                    Set-Team -GroupId $($UnifiedGroup.id) `
                        -AllowCreateUpdateRemoveConnectors $AllowCreateUpdateRemoveConnectors `
                        -AllowCreateUpdateChannels $AllowCreateUpdateChannels `
                        -AllowDeleteChannels $AllowDeleteChannels `
                        -AllowAddRemoveApps $AllowAddRemoveApps `
                        -AllowCreateUpdateRemoveTabs $AllowCreateUpdateRemoveTabs `
                        -ErrorAction Stop | Out-Null
                
                    Write-output "Teams is geactiveerd voor site [$Alias]."
                    Write-Log -LogOutput ("Teams is geactiveerd voor site [$Alias].") -Path $FilePath
                }
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het activeren van Teams voor site [$Alias] is mislukt. $_") -Path $FilePath             
                Write-Error "Het activeren van Teams voor site [$Alias] is mislukt. $_"
            }
        }
    }
}

##################  Prerequisties ##################

# Get credentials
$AutomationCredential = Get-AutomationPSCredential -Name "Creds"
$userName = $AutomationCredential.UserName  
$securePassword = $AutomationCredential.Password
$psCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userName, $securePassword

##################  Main logic ##################

$global:ErrorCount = 0
$TestUser = Test-AllowedUser -UserPrincipalName $RespondersEmail -GroupName $SelfServiceGroup

if($TestUser){
    # Check if group already exist
    $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$GroupName')"
    $cGroup = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value.displayName

    if(-not(!$cGroup)){
        $global:ErrorCount += 1
        Write-Log -LogOutput ("De opgegeven groep [$GroupName] bestaat al gebruik Groep bijwerken via de selfservice portal.") -Path $FilePath
        Write-Error "De opgegeven groep [$GroupName] bestaat al gebruik Groep bijwerken via de selfservice portal."     
    }

    # Get allowed custom domains tenant
    $verifiedDomains = @()
    $uri = "https://graph.microsoft.com/v1.0/domains"
    $customDomains = ((Invoke-RestMethod -Uri $uri -Headers $($global:authHeader) -Method Get).value | Select-Object id,isVerified)

    foreach($domain in $customDomains){
        if($domain.isVerified -eq $true){
            $verifiedDomains += $domain.id
        }
    }

    # Email domain for Microsoft365 group
    if($Type -eq 'Microsoft365'){
        if($EmailDomain -in $verifiedDomains){
        }else{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Het opgegeven domein [$EmailDomain] is niet toegestaan voor de Microsoft 365 groep.") -Path $FilePath
            Write-Error "Het opgegeven domein [$EmailDomain] is niet toegestaan voor de Microsoft 365 groep."
        }
    }

    # Email domain for distribution list
    if(-not(!$DLEmail)){
        $findchar = $DLEmail.IndexOf("@")
        $DLDomain = $DLEmail.Substring($findchar+1)

        if($DLDomain -in $verifiedDomains){
        }else{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Het opgegeven domein [$DLDomain] is niet toegestaan voor de distributielijst.") -Path $FilePath
            Write-Error "Het opgegeven domein [$DLDomain] is niet toegestaan voor de distributielijst."
        }
    }

    if($global:ErrorCount -eq 0){
        if(($Type -eq 'Microsoft365') -or ($Type -eq 'Distributielijst')){
            try{
                Connect-ExchangeOnline -Credential $psCredential -WarningAction Ignore
                Write-output "[$userName] verbonden met Exchange Online."
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Verbinding naar Exchange Online mislukt met automation account [$userName]. $_") -Path $FilePath   
                Write-Error "Verbinding naar Exchange Online mislukt met automation account [$userName]. $_"
            }
        }    

        if($Type -eq 'Microsoft365'){
            try{
                Connect-SPOService -Url "https://$($TenantName)-admin.sharepoint.com" -Credential $psCredential
                Write-output "[$userName] verbonden met SharePoint Online."
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Verbinding naar SharePoint Online mislukt met automation account [$userName]. $_") -Path $FilePath   
                Write-Error "Verbinding naar SharePoint Online mislukt met automation account [$userName]. $_"
            }
        }

        if($Teams -like 'true'){
            try{
                Connect-MicrosoftTeams -Credential $psCredential -WarningAction Ignore
                Write-output "[$userName] verbonden met Microsoft Teams."
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Verbinding naar Microsoft Teams mislukt met automation account [$userName]. $_"  ) -Path $FilePath   
                Write-Error "Verbinding naar Microsoft Teams mislukt met automation account [$userName]. $_"     
            }
        }
    }

    if($global:ErrorCount -eq 0){
        # Generieke O365 groep instellingen
        if($SPOReadOnlyGroup -like 'ja'){[bool]$ReadOnlyGroup=$true}
        if($Sharing -like 'true'){[bool]$sharingEnabled=$true}
        if($Teams -like 'true'){[bool]$Teams=$true}

        # region O365
        if($Type -eq 'Microsoft365'){
            $DisplayName = $GroupName.Trim()
            $Alias = $DisplayName.Replace(' ','').Replace('&','').ToLower().Trim()
            $EmailAddress = "$Alias@groups.$($EmailDomain)"
            $AccessType = 'Private'
            
            # Check if ReadOnlyGroup exist otherwise create it
            if($ReadOnlyGroup){
                try{
                    $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'sp_bezoeker_$Alias')"
                    $ReadOnlyGroupExist = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value

                    if(-not($ReadOnlyGroupExist)){
                        $JSON = @{
                            displayName = "sp_bezoeker_$Alias"
                            mailEnabled = $false
                            mailNickname = "$DisplayName"
                            securityEnabled = $true
                            description = "SharePoint $Alias alleen lezen"
                        } | ConvertTo-Json       

                        $Uri = "https://graph.microsoft.com/v1.0/groups"
                        (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method POST -ContentType "application/json" -Body $JSON)
                        Write-output "SharePoint leesgroep [sp_bezoeker_$Alias] is aangemaakt." 
                        Write-Log -LogOutput ("SharePoint leesgroep [sp_bezoeker_$Alias] is aangemaakt.") -Path $FilePath
                    }else{
                        Write-output "SharePoint leesgroep [sp_bezoeker_$Alias] bestaat al." 
                        Write-Log -LogOutput ("SharePoint leesgroep [sp_bezoeker_$Alias] bestaat al.") -Path $FilePath                     
                    }
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("het is niet gelukt om SharePoint leesgroep [sp_bezoeker_$Alias] aan te maken. $_") -Path $FilePath              
                    Write-error "het is niet gelukt om SharePoint leesgroep [sp_bezoeker_$Alias] aan te maken. $_"
                }
            }

            if($global:ErrorCount -eq 0){
                $Params = @{
                    DisplayName = "$DisplayName"
                    Alias = "$Alias"
                    AccessType = "$AccessType"
                    EmailAddress = "$EmailAddress"
                    Language = "$Language"
                    RequireSenderAuthenticationEnabled = $true
                    tenantName = "$TenantName"
                    ConditionalAccessPolicy ="AllowLimitedAccess"
                    Verbose = $true
                }

                if($Teams){
                    $Params.add("teams",$true)
                    $Params.add("AllowCreateUpdateRemoveTabs", $true)
                    $Params.add("AllowAddRemoveApps", $true)
                    $Params.add("AllowDeleteChannels", $true)
                    $Params.add("AllowCreateUpdateChannels", $true)
                    $Params.add("AllowCreateUpdateRemoveConnectors", $true)
                }
                if($sharingEnabled){
                    $Params.add("EnableSharing",$true)
                }      

                Add-OfficeGroup @Params
            }
        }
    }

    if($global:ErrorCount -eq 0){
        if(($ReadOnlyGroup) -and ($Type -eq 'Microsoft365')){
            $GroupName = "$($GroupName.Trim()) Visitors"
            $Alias = $DisplayName.Replace(' ','').Replace('&','').ToLower().Trim()
            $LoginName = "sp_bezoeker_$Alias"
            [bool]$Success = $false
            $n = 1
            do{
                try{
                    Add-SPOUser -Group $GroupName -LoginName $LoginName -Site "https://$($TenantName).sharepoint.com/sites/$Alias" -ErrorAction Stop
                    Write-output "Groep [$LoginName] toegevoegd aan site [$DisplayName]." 
                    Write-Log -LogOutput ("Groep [$LoginName] toegevoegd aan site [$DisplayName].") -Path $FilePath                  
                    [bool]$Success = $true
                }
                catch{
                    [bool]$Success=$false
                    Write-Host 'wacht 15 seconden'
                    Start-Sleep -Seconds 15
                    $n++
                }
            }until (($Success) -or ($n -eq 10))

            if($Success){
            }else{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het is niet gelukt om groep [$LoginName] toe te voegen aan site [$Alias].") -Path $FilePath
                Write-Error "Het is niet gelukt om groep [$LoginName] toe te voegen aan site [$Alias]."
            }
        }
    }
    # endregion O365

    if($global:ErrorCount -eq 0){
        # region SEC
        if(($Type -eq 'Security') -and ($CloudGroup -like 'false')){
            # Aanmaken onprem groep
            $DisplayName = "$($GroupName.tolower().Trim())"
            $SamAccountName = $GroupName.replace(' ','').tolower()

            try {

                $Params = @{
                    Name = $DisplayName
                    SamAccountName = $SamAccountName
                    GroupCategory = "Security"
                    GroupScope = "Global"
                    Description = $GroupDescription
                    DisplayName = $DisplayName
                    Path = $LDAPGroupPath 
                }

                New-ADGroup @Params -Server $Server -Credential $psCredential

                Write-output "Security groep [$displayName] is aangemaakt in domein [$Server]."
                Write-Log -LogOutput ("Security groep [$displayName] is aangemaakt in domein [$Server].") -Path $FilePath   

            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het is niet gelukt om security groep [$displayName] aan te maken in domein [$Server]. $_") -Path $FilePath   
                Write-error "Het is niet gelukt om security groep [$displayName] aan te maken in domein [$Server]. $_"
            }

        }elseif(($Type -eq 'Security') -and ($CloudGroup -like 'true')){
            # Aanmaken cloud groep
            try{    
                $DisplayName = "$($GroupName.tolower().Trim())"

                if($RoleAssignable -like 'true'){
                    Write-output "Rollen toekennen mogelijk voor security groep [$displayName]."
                    Write-Log -LogOutput ("Rollen toekennen mogelijk voor security groep [$displayName].") -Path $FilePath

                    $JSON = @{
                        displayName = "$DisplayName"
                        isAssignableToRole = $true
                        mailEnabled = $false
                        mailNickname = "$DisplayName"
                        securityEnabled = $true
                        description = "$GroupDescription"
                    } | ConvertTo-Json

                }
                else{
                    $JSON = @{
                        displayName = "$DisplayName"
                        isAssignableToRole = $true
                        mailEnabled = $false
                        mailNickname = "$DisplayName"
                        securityEnabled = $true
                        description = "$GroupDescription"
                    } | ConvertTo-Json       
                }

                $Uri = "https://graph.microsoft.com/v1.0/groups"
                (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method POST -ContentType "application/json" -Body $JSON)

                Write-output "Security groep [$displayName] is aangemaakt in de tenant [$TenantName]."
                Write-Log -LogOutput ("Security groep [$displayName] is aangemaakt in de tenant [$TenantName].") -Path $FilePath              
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het is niet gelukt om security groep [$displayName] aan te maken in de tenant [$TenantName]. $_") -Path $FilePath   
                Write-error "Het is niet gelukt om security groep [$displayName] aan te maken in de tenant [$TenantName]. $_"
            }
        }
    }
        # endregion SEC

    if($global:ErrorCount -eq 0){
        # region DL
        if($Type -eq 'Distributielijst'){
            try{
                $DisplayName = $GroupName.Trim()
                $Alias = "DL-$($GroupName.tolower().replace(' ','').Trim())"
                $PrimarySmtpAddress=if($Email -like 'true'){"$DLEmail"}else{"$($Alias.tolower())`@$EmailDomain"}
                [bool]$RequireSenderAuthenticationEnabled = if($Email -like 'true'){$false}else{$true}
                
                New-DistributionGroup -DisplayName $DisplayName `
                    -Name $Alias `
                    -Description $GroupDescription `
                    -RequireSenderAuthenticationEnabled $RequireSenderAuthenticationEnabled `
                    -PrimarySmtpAddress $PrimarySmtpAddress

                Write-output "Distributielijst [$displayName] is aangemaakt."
                Write-Log -LogOutput ("Distributielijst [$displayName] is aangemaakt.") -Path $FilePath 
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput (("Het is niet gelukt om distributie lijst [$displayName] aan te maken. $_")) -Path $FilePath  
                Write-error ("Het is niet gelukt om distributie lijst [$displayName] aan te maken. $_")
            }
        }
    }
        # endregion DL

    try {
        Invoke-RetryCmdlet -Cmdlet {$null = Disconnect-SPOService -Confirm:$false}
        Invoke-RetryCmdlet -Cmdlet {$null = Disconnect-ExchangeOnline -Confirm:$false}	
        Invoke-RetryCmdlet -Cmdlet {$null = Disconnect-MicrosoftTeams -Confirm:$false}		
        Write-output "Verbinding external services verbreken"
    }catch {}

    if($global:ErrorCount -eq 0){
        $Subject = "Selfservice [$File] door [$RespondersEmail] uitgevoerd"
        $Body = "Gebruiker [$RespondersEmail] heeft via Selfservice [$File] uitgevoerd [$CustomerId]. Zie bijlage voor meer info."
        Send-Mail -Recipients $Recipients -Recipientscc $RecipientsCC -Subject $Subject -Body $Body -MailSender $MailSender -Attachments $FilePath
        Remove-item -Path $FilePath
    }
    else{
        $Subject = "Selfservice [$File] door [$RespondersEmail] mislukt"
        $Body = "Gebruiker [$RespondersEmail] heeft via Selfservice [$File] uitgevoerd [$CustomerId]. Er zijn [$global:ErrorCount] opgetreden zie bijlage voor meer info."
        Send-Mail -Recipients $Recipients -Recipientscc $RecipientsCC -Subject $Subject -Body $Body -MailSender $MailSender -Attachments $FilePath
        Remove-item -Path $FilePath
    }
}
else{
    $Subject = "Selfservice [$File] door [$RespondersEmail] niet gemachtigd"
    $Body = "Gebruiker [$RespondersEmail] heeft via Selfservice een [$File] uitgevoerd [$CustomerId]. Deze gebruiker is niet geauthoriseerd voor deze actie."
    Send-Mail -Recipients $Recipients -Recipientscc $RecipientsCC -Subject $Subject -Body $Body -MailSender $MailSender
    Write-output "Email verstuurd aan [$Recipients][$RecipientsCC]" 
}