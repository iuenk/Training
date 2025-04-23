#=============================================================================================================================
#
# Script Name:     change-group.ps1
# Description:     Possible to change the description of onpremise and cloud security groups, distribution groups
#                  Microsoft 365 groups and enable external sharing and Teams.
#   
# Notes      :     
#
# Created by :     Ivo Uenk
# Date       :     3-7-2024
# Version    :     1.0
#=============================================================================================================================

Param (
  [string] $CustomerId,
  [string] $GroupName,
  [string] $GroupDescription,
  [string] $RespondersEmail,
  [boolean] $Teams,
  [boolean] $Sharing
)

#. .\AppRunEnv.ps1
. .\AppMail.ps1
. .\AppAuthHeader.ps1
. .\AppTestAllowedUser.ps1
. .\AppRetryCmdlet.ps1
. .\AppWriteLog.ps1

################## Variables ##################

$File = "Wijzigen-Groep" + "-" + ((Get-Date).ToString("dd-MM-yyyy-HHmm"))
$FilePath = $env:TEMP + "\" + $File + ".log"
$SelfServiceGroup = Get-AutomationVariable -Name "SelfServiceGroup"

$MailSender = Get-AutomationVariable -Name "EmailAutomation"
$Recipient = $RespondersEmail
$Recipients = $Recipient.Split(",")
$RecipientCC = Get-AutomationVariable -Name "EmailSupport"
$RecipientsCC = $RecipientCC.Split(",")

$TenantName = Get-AutomationVariable -Name "TenantName"
$SharingDomain = Get-AutomationVariable -Name "SharingDomain"
$SharingDomain = $SharingDomain.Split(",")

$Server = Get-AutomationVariable -Name "OnPremDomain"

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
    # Retrieve group info
    $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$GroupName')"
    $cGroup = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value

    if($($cGroup.securityEnabled) -eq $false){
        try{
            Write-output "verbinding met exchange maken"
            Connect-ExchangeOnline -Credential $psCredential -WarningAction Ignore
            Write-output "[$userName] verbonden met Exchange Online."
        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Verbinding naar Exchange Online mislukt met automation account [$userName]. $_") -Path $FilePath   
            Write-Error "Verbinding naar Exchange Online mislukt met automation account [$userName]. $_"
        }
    }    

    if(($($cGroup.securityEnabled) -eq $false) -and ($($cGroup.mail) -like "*@groups*")){
        try{
            Write-output "verbinding met SharePoint maken"
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
            Write-output "verbinding met Teams maken"
            Connect-MicrosoftTeams -Credential $psCredential -WarningAction Ignore
            Write-output "[$userName] verbonden met Microsoft Teams."
        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Verbinding naar Microsoft Teams mislukt met automation account [$userName]. $_"  ) -Path $FilePath   
            Write-Error "Verbinding naar Microsoft Teams mislukt met automation account [$userName]. $_"     
        }
    }

    if($global:ErrorCount -eq 0){
        # Generic O365 settings
        if($Sharing -like 'true'){[bool]$sharingEnabled=$true}
        if($Teams -like 'true'){[bool]$Teams=$true}

        # region O365
        if(($($cGroup.securityEnabled) -eq $false) -and ($($cGroup.mail) -like "*@groups*")){

            # Update unified group description if needed
            if($($cGroup.description) -ne $GroupDescription){
                try{              
                    Set-UnifiedGroup -Identity $GroupName -Notes $GroupDescription

                    Write-output "Beschrijving voor unified groep [$GroupName] gewijzigd naar [$GroupDescription]."
                    Write-Log -LogOutput ("Beschrijving voor unified groep [$GroupName] gewijzigd naar [$GroupDescription].") -Path $FilePath
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het wijzigen van de beschrijving van unified groep [$GroupName] is mislukt. $_") -Path $FilePath             
                    Write-Error "Het wijzigen van de beschrijving van unified groep [$GroupName] is mislukt. $_"
                }                
            }

            # Get SPO site info
            $SPOSiteUrl = (Get-SPOSite -Limit all | Where-Object {$_.url -like "*/sites/$GroupName"}).Url
            $SPOSiteDetails = Get-SPOSite -Identity $SPOSiteUrl -Detailed | Select-Object SharingCapability,ConditionalAccessPolicy,IsTeamsConnected

            # Activate Teams for SPO Site
            if(($Teams) -and ($($SPOSiteDetails.IsTeamsConnected) -eq $false)){
                try{
                    New-Team -Group $($cGroup.id) -ErrorAction Stop | out-null
                    Set-Team -GroupId $($cGroup.id) `
                        -AllowCreateUpdateRemoveConnectors $true `
                        -AllowCreateUpdateChannels $true `
                        -AllowDeleteChannels $true `
                        -AllowAddRemoveApps $true `
                        -AllowCreateUpdateRemoveTabs $true `
                        -ErrorAction Stop | Out-Null
            
                    Write-output "Teams is geactiveerd voor SPO site [$GroupName]."
                    Write-Log -LogOutput ("Teams is geactiveerd voor SPO site [$GroupName].") -Path $FilePath
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het activeren van Teams voor SPO site [$GroupName] is mislukt. $_") -Path $FilePath             
                    Write-Error "Het activeren van Teams voor SPO site [$GroupName] is mislukt. $_"
                }
            }elseif(($Teams) -and ($($SPOSiteDetails.IsTeamsConnected) -eq $true)){
                Write-output "Teams is al geactiveerd voor SPO site [$GroupName]."
                Write-Log -LogOutput ("Teams is al geactiveerd voor SPO site [$GroupName].") -Path $FilePath   
            }

            # Configure external sharing for SPO site
            if(($sharingEnabled) -and ($($SPOSiteDetails.SharingCapability) -eq "Disabled")){
                $ConditionalAccessPolicy = "AllowLimitedAccess"

                try{
                    Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$GroupName" -SharingCapability 'ExternalUserSharingOnly' -ErrorAction Stop | Out-Null
                    Write-output "Aanzetten ExternalUserSharingOnly voor SPO site [$GroupName]."
                    Write-Log -LogOutput ("Aanzetten ExternalUserSharingOnly voor SPO site[$GroupName].") -Path $FilePath
    
                    if($SharingDomain){
                        Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$GroupName" -SharingAllowedDomainList "$SharingDomain" -SharingDomainRestrictionMode 'allowlist' -ErrorAction Stop | Out-Null
                    }
        
                    if($ConditionalAccessPolicy){
                        Set-SPOSite -Identity "https://$TenantName.sharepoint.com/sites/$GroupName" -ConditionalAccessPolicy $ConditionalAccessPolicy -ErrorAction Stop | Out-Null
                        Write-output "Instellen CA Policy [$ConditionalAccessPolicy] voor SPO site [$GroupName]."
                        Write-Log -LogOutput ("Instellen CA Policy [$ConditionalAccessPolicy] voor SPO site [$GroupName].") -Path $FilePath
                    }
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het configureren van SPO site [$GroupName] is mislukt. $_") -Path $FilePath               
                    Write-Error "Het configureren van SPO site [$GroupName] is mislukt. $_"
                }
            }elseif(($sharingEnabled) -and ($($SPOSiteDetails.SharingCapability) -eq "Enabled")){
                Write-output "Extern delen al ingeschakeld voor SPO site [$GroupName]."
                Write-Log -LogOutput ("Extern delen al ingeschakeld voor SPO site [$GroupName].") -Path $FilePath   
            }      
        }elseif(($($cGroup.securityEnabled) -eq $false) -and ($($cGroup.mail) -ne "*@groups*")){
            # Update description distribution group
            if($($cGroup.description) -ne $GroupDescription){
                try{
                    Set-DistributionGroup -Identity $GroupName -Description $GroupDescription

                    Write-output "Distributielijst [$GroupName] beschrijving gewijzigd naar [$GroupDescription]."
                    Write-Log -LogOutput ("Distributielijst [$GroupName] beschrijving gewijzigd naar [$GroupDescription].") -Path $FilePath
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het wijzigen van de beschrijving van distributie groep [$GroupName] is mislukt. $_") -Path $FilePath  
                    Write-error ("Het wijzigen van de beschrijving van distributie groep [$GroupName] is mislukt. $_")
                }
            }
        }
    }
    # endregion O365

    if($global:ErrorCount -eq 0){
        # region SEC
        if(($($cGroup.securityEnabled) -eq $true) -and ($($cGroup.onPremisesSyncEnabled) -eq $true)){
            # Modify onprem group
            if($($cGroup.description) -ne $GroupDescription){
                try{
                    Get-ADGroup -Identity $GroupName | Set-ADGroup -Description $GroupDescription -Server $Server -Credential $psCredential

                    Write-output "Security groep [$GroupName] beschrijving is gewijzigd naar [$GroupDescription] in domein [$Server]."
                    Write-Log -LogOutput ("Security groep [$GroupName] beschrijving is gewijzigd naar [$GroupDescription] in domein [$Server].") -Path $FilePath
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het wijzigen van de beschrijving van security groep [$GroupName] is mislukt. $_") -Path $FilePath   
                    Write-error "Het wijzigen van de beschrijving van security groep [$GroupName] is mislukt. $_"
                }
            }
        }

        if(($($cGroup.securityEnabled) -eq $true) -and ($null -eq $($cGroup.onPremisesSyncEnabled))){            
            # Modify cloud group
            if($($cGroup.description) -ne $GroupDescription){
                try{
                    $JSON = @{
                        displayName = "$GroupName"
                        description = "$GroupDescription"
                    } | ConvertTo-Json

                    $Uri = "https://graph.microsoft.com/v1.0/groups/$($cGroup.id)"
                    (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method PATCH -ContentType "application/json" -Body $JSON)

                    Write-output "Security groep [$GroupName] beschrijving is gewijzigd in de tenant [$TenantName]."
                    Write-Log -LogOutput ("Security groep [$GroupName] beschrijving is gewijzigd in de tenant [$TenantName].") -Path $FilePath
                }catch{
                    $global:ErrorCount += 1
                    Write-Log -LogOutput ("Het is niet gelukt om security groep [$GroupName] beschrijving te wijzigen in de tenant [$TenantName]. $_") -Path $FilePath   
                    Write-error "Het is niet gelukt om security groep [$GroupName] beschrijving te wijzigen in de tenant [$TenantName]. $_"
                }
            }
        }
    }
    # endregion SEC

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