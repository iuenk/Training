#=============================================================================================================================
#
# Script Name:     AppRemoveUser.ps1
# Description:     Disable or remove onpremise or cloud user(s).
#   
# Notes      :     Possible to bulk disable or remove users.
#                  Disable user(s):
#                  1. Unsharing files on their onedrive send access link for delegate/manager.
#                  2. Remove inbox rules and calendar items, hide mailbox, convert to shared mailbox when <50GB.
#                  3. Give delegate(s) permissions on mailbox and set forwarder.
#                  
#                  Remove users: remove users without additional actions beeing done.
#
# Created by :     Ivo Uenk
# Date       :     16-7-2024
# Version    :     1.0
#=============================================================================================================================

Param (
  [string] $Users,
  [string] $Delegates,
  [string] $CustomerId,
  [boolean] $DisableAccounts,
  [boolean] $RemoveAccounts,
  [string] $RespondersEmail
)

#. .\AppRunEnv.ps1
. .\AppMail.ps1
. .\AppAuthHeader.ps1
. .\AppTestAllowedUser.ps1
. .\AppWriteLog.ps1

################## Variables ##################

$File = "Verwijderen-Gebruikers" + "-" + ((Get-Date).ToString("dd-MM-yyyy-HHmm"))
$FilePath = $env:TEMP + "\" + $File + ".log"
$SelfServiceGroup = Get-AutomationVariable -Name "SelfServiceGroup"

$MailSender = Get-AutomationVariable -Name "EmailAutomation"
$Recipient = $RespondersEmail
$Recipients = $Recipient.Split(",")
$RecipientCC = Get-AutomationVariable -Name "EmailSupport"
$RecipientsCC = $RecipientCC.Split(",")

$TenantName = Get-AutomationVariable -Name "TenantName"
$Server = Get-AutomationVariable -Name "OnPremDomain"

$Users = $Users.Split(",")
$Delegates = $Delegates.Split(",")

##################  Prerequisties ##################

# Mail style
$css = "<html>
<head>
<style>
table, th, td {
border: 0;
width: 580px;
}
th, td {
padding: 5px;
}
th {
text-align: left;
font-family: Arial, Helvetica, Helvetica Neue, sans-serif;
font-size: 18px;
color: #e63532;
}
td {
text-align: left;
font-family: Arial, Helvetica, Helvetica Neue, sans-serif;
font-size: 11pt;
color: #333333;
}
</style>
</head>"

# Mail body
$body = "<body>
<center>
<table>
<tr><td>Beste DELEGATE_DISPLAYNAME,</td></tr>
<tr><td></td></tr>
<tr><th>U heeft toegang gekregen tot de OneDrive van USER_DISPLAYNAME. Ook heeft u rechten gekregen op de mailbox.</th></tr>
<tr><td></td></tr>
<tr><td>U heeft tot ENDDATE_RETENTION om de gegevens van USER_DISPLAYNAME veilig te stellen.</td></tr>
<tr><td></td></tr>
<tr><td>Met deze URL <a href=ONEDRIVE_URL><b>OneDrive locatie</b></a> kunt u de bestanden bekijk en downloaden van gebruiker USER_DISPLAYNAME.</td></tr>
</table>
</center>
</body></html>"

# Get credentials
$AutomationCredential = Get-AutomationPSCredential -Name "LangoCreds"
$userName = $AutomationCredential.UserName  
$securePassword = $AutomationCredential.Password
$psCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userName, $securePassword

##################  Main logic ##################

$global:ErrorCount = 0
$removeLicenses = 0

$TestUser = Test-AllowedUser -UserPrincipalName $RespondersEmail -GroupName $SelfServiceGroup

if($TestUser){
    if($DisableAccounts -like 'true'){
        try{
            Connect-ExchangeOnline -Credential $psCredential -WarningAction Ignore
            Write-output "[$userName] verbonden met Exchange Online."

            Connect-SPOService -Url "https://$($TenantName)-admin.sharepoint.com" -Credential $psCredential
            Write-output "[$userName] verbonden met SharePoint Online."
        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Verbinding naar MS diensten mislukt met automation account [$userName]. $_") -Path $FilePath   
            Write-Error "Verbinding naar MS diensten mislukt met automation account [$userName]. $_"
        }
    }

    if($global:ErrorCount -eq 0){
        if($DisableAccounts -like 'true'){
            try{
                # Get all groups that have licenses assigned
                $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=assignedLicenses/any()"
                $LicenseGroups = (Invoke-RestMethod -Uri $uri -Headers $($global:authHeader) -Method Get).value | Select-Object id,displayName,onPremisesSamAccountName,membershipRule,onPremisesSyncEnabled
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het is niet gelukt om groepen op te halen controleer rechten. $_") -Path $FilePath   
                Write-Error "Het is niet gelukt om groepen op te halen controleer rechten. $_"
            }
        }
    }

    if($global:ErrorCount -eq 0){
        foreach ($User in $Users){
            try{
                $Uri = "https://graph.microsoft.com/v1.0/users/$($User)?`$select=id,userPrincipalName,displayName,accountEnabled,mail,onPremisesSamAccountName,onPremisesSyncEnabled"
                $UserInfo = Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get
            }catch{
                $global:ErrorCount += 1
                Write-Log -LogOutput ("Het is niet gelukt om informatie op te halen voor gebruiker [$User].") -Path $FilePath
                Write-Error "Het is niet gelukt om informatie op te halen voor gebruiker [$User]."
            }

            if($global:ErrorCount -eq 0){
                if($DisableAccounts -like 'true'){
                    ###### Start disabling user accounts ######
                    if($($UserInfo.accountEnabled) -eq $true){
                        if($UserInfo.onPremisesSyncEnabled -eq $true){
                            # Start disabling user account onprem                 
                            try{
                                Disable-ADAccount -Identity $($UserInfo.onPremisesSamAccountName) -Server $Server -Credential $psCredential
                                
                                Write-Output "Gebruiker [$User] uitgeschakeld in domein [$Server]."
                                Write-Log -LogOutput ("Gebruiker [$User] uitgeschakeld in domein [$Server].") -Path $FilePath                         
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om gebruiker [$User] uit te schakelen in domein [$Server]. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om gebruiker [$User] uit te schakelen in domein [$Server]. $_"
                            }                
                        }else{
                            # Start disabling user account in Entra ID
                            try{
                                $JSON = @{
                                    accountEnabled = $false
                                } | ConvertTo-Json

                                $Uri = "https://graph.microsoft.com/v1.0/users/$($UserInfo.id)"
                                Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Patch -ContentType "application/json" -Body $JSON

                                Write-Output "Gebruiker [$User] uitgeschakeld in tenant [$TenantName]."
                                Write-Log -LogOutput ("Gebruiker [$User] uitgeschakeld in tenant [$TenantName].") -Path $FilePath      
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om gebruiker [$User] uit te schakelen in tenant [$TenantName]. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om gebruiker [$User] uit te schakelen in tenant [$TenantName]. $_"
                            }
                        }
                    }else{
                        Write-output "Gebruiker [$User] is al uitgeschakeld."
                        Write-Log -LogOutput ("Gebruiker [$User] is al uitgeschakeld.") -Path $FilePath
                    }

                    if($global:ErrorCount -eq 0){
                        ###### Start mailbox actions ######
                        $Mailbox = Get-Mailbox -Identity $($UserInfo.mail) -ErrorAction SilentlyContinue

                        #Remove inbox rules and calendar items, hide mailbox, convert to shared mailbox when <50GB
                        if(-not(!$Mailbox)){
                            try{
                                # Make mailbox hidden
                                if($UserInfo.onPremisesSyncEnabled -eq $true){
                                    Set-ADUser -Identity $($UserInfo.onPremisesSamAccountName) -Replace @{msExchHideFromAddressLists=$true} -Server $Server -Credential $psCredential
                                }else{
                                    Set-Mailbox -Identity $($UserInfo.mail) -HiddenFromAddressListsEnabled $true
                                }

                                # Remove all calendar meetings for the mailbox
                                Remove-CalendarEvents -Identity $($UserInfo.mail) -CancelOrganizedMeetings -Confirm:$False -QueryWindowInDays 1825
                                Write-Output "Verwijder agenda afspraken voor [$($UserInfo.mail)]."
                                Write-Log -LogOutput ("Verwijder agenda afspraken voor [$($UserInfo.mail)].") -Path $FilePath 

                                # Remove rules on the mailbox
                                Get-InboxRule -Mailbox $($UserInfo.mail) -BypassScopeCheck -ErrorAction SilentlyContinue | `
                                ForEach-Object {Remove-InboxRule -Identity $_.Identity -AlwaysDeleteOutlookRulesBlob -Confirm:$False -Force -ErrorAction Stop}
                                Write-Output "Inbox regels weggehaald voor mailbox [$($UserInfo.mail)]."
                                Write-Log -LogOutput ("Inbox regels weggehaald voor mailbox [$($UserInfo.mail)].") -Path $FilePath 

                                # Check if mailbox is larger than 50GB and convert it to shared mailbox
                                $Stats = (Get-MailboxStatistics -Identity $($UserInfo.mail) | Select-Object DisplayName, @{Name="TotalItemSizeMB"; Expression={[math]::Round(($_.TotalItemSize.ToString().Split("(")[1].Split(" ")[0].Replace(",","")/1MB),0)}})
                                $Size = $Stats.TotalItemSizeMB
                                Write-Output "Mailbox [$($UserInfo.mail)] is [$Size MB]."
                                Write-Log -LogOutput ("Mailbox [$($UserInfo.mail)] is [$Size MB].") -Path $FilePath 

                                if($Size -le 50000){
                                    # Convert mailbox to Shared mailbox and wait till done
                                    Set-Mailbox -Identity $($UserInfo.mail) -Type Shared

                                    $MailboxType = ""
                                    $condition = ($mailboxType -eq "SharedMailbox")
                                    while(!$condition){
                                        if($cMailboxType -ne $mailboxType){Write-output "Mailbox [$($UserInfo.mail)] nog niet omgezet naar SharedMailbox."}
                                        $cMailboxType = $mailboxType
                                        Start-Sleep -Seconds 5
                                                    
                                        $mailboxType = (Get-mailbox -Identity $($UserInfo.mail)).RecipientTypeDetails
                                        $condition = ($mailboxType -eq "SharedMailbox")      
                                    }
                                    Write-Output "Mailbox [$($UserInfo.mail)] omgezet naar [$mailboxType]." 
                                    Write-Log -LogOutput ("Mailbox [$($UserInfo.mail)] omgezet naar [$mailboxType].") -Path $FilePath

                                }else{
                                    # License cannot be removed because mailbox is not converted to SharedMailbox +1
                                    $removeLicenses += 1
                                    Write-Output "Mailbox [$($UserInfo.mail)] gelijk aan of groter dan 50GB te groot om omgezet te worden naar shared mailbox."
                                    Write-Log -LogOutput ("Mailbox [$($UserInfo.mail)] gelijk aan of groter dan 50GB te groot om omgezet te worden naar shared mailbox.") -Path $FilePath
                                }

                                # Give delegate(s) permissions on mailbox (shared or not shared) and set forwarder
                                foreach($Delegate in $Delegates){
                                    $Uri = "https://graph.microsoft.com/v1.0/users/$($Delegate)?`$select=id,displayName,userPrincipalName,mail"
                                    $DelegateInfo = Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get

                                    # Set forwarder on mailbox
                                    Set-Mailbox -Identity $($UserInfo.mail) -DeliverToMailboxAndForward $false -ForwardingSMTPAddress $($DelegateInfo.mail)
                                    Write-Output "Forwarder [$($DelegateInfo.mail)] ingesteld voor shared mailbox [$($UserInfo.mail)]."
                                    Write-Log -LogOutput ("Forwarder [$($DelegateInfo.mail)] ingesteld voor shared mailbox [$($UserInfo.mail)].") -Path $FilePath 

                                    # Set permissions on mailbox
                                    Add-MailboxPermission -Identity $($UserInfo.mail) -User $($DelegateInfo.mail) -AccessRights FullAccess -InheritanceType All -AutoMapping $false
                                    Write-Output "Geef [$($DelegateInfo.mail)] volledige toegang op shared mailbox [$($UserInfo.mail)]."
                                    Write-Log -LogOutput ("Geef [$($DelegateInfo.mail)] volledige toegang op shared mailbox [$($UserInfo.mail)].") -Path $FilePath
                                }
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om mailbox [$($UserInfo.mail)] van gebruiker [$($UserInfo.userPrincipalName)] om te zetten. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om mailbox [$($UserInfo.mail)] van gebruiker [$($UserInfo.userPrincipalName)] om te zetten. $_"                    
                            }
                        }else{
                            Write-output "Geen mailbox gevonden voor gebruiker [$User]."
                            Write-Log -LogOutput ("Geen mailbox gevonden voor gebruiker [$User].") -Path $FilePath
                        }
                    }

                    if($global:ErrorCount -eq 0){
                        ###### Start OneDrive actions ######
                        # Onedrive actions here Unsharing files on their onedrive send access link for delegate/manager
                        $SPOsite = (Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Owner -eq '$($UserInfo.userPrincipalName)'" | Select-Object Url,owner,@{label="Size in MB";Expression={$_.StorageUsageCurrent/1MB}})

                        if(-not(!$SPOSite)){
                            Set-SPOSite -Identity $($SPOsite.Url) -SharingCapability Disabled
                            Write-output "Data is niet meer gedeeld op OneDrive van gebruiker [$User]."
                            Write-Log -LogOutput ("Data is niet meer gedeeld op OneDrive van gebruiker [$User].") -Path $FilePath   

                            foreach($Delegate in $Delegates){
                                $Uri = "https://graph.microsoft.com/v1.0/users/$($Delegate)?`$select=id,displayName,userPrincipalName,mail"
                                $DelegateInfo = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get)

                                Set-SPOUser -Site $($SPOsite.Url) -LoginName $($DelegateInfo.userPrincipalName) -IsSiteCollectionAdmin $true
                                Write-output "Delegate [$($DelegateInfo.userPrincipalName)] ingesteld als site collection admin op OneDrive van gebruiker [$User]."
                                Write-Log -LogOutput ("Delegate [$($DelegateInfo.userPrincipalName)] ingesteld als site collection admin op OneDrive van gebruiker [$User].") -Path $FilePath  

                                # Send email with link to OneDrive user
                                $mailTemplate = $css + $body
                                $Subject = "U heeft toegang gekregen tot de OneDrive van gebruiker $User"

                                try{
                                    # Send mail here
                                    $bodyTemplate = $mailTemplate
                                    $bodyTemplate = $bodyTemplate.Replace('ONEDRIVE_URL', $($SPOsite.Url))
                                    $bodyTemplate = $bodyTemplate.Replace('ENDDATE_RETENTION', (Get-date).AddDays(30).ToString('dd-MM-yyyy'))
                                    $bodyTemplate = $bodyTemplate.Replace('USER_DISPLAYNAME', $($UserInfo.displayName))
                                    $bodyTemplate = $bodyTemplate.Replace('DELEGATE_DISPLAYNAME', $($DelegateInfo.displayName))

                                    Send-Mail -Recipients $($DelegateInfo.mail) -Subject $Subject -Body $bodyTemplate -MailSender $MailSender
                                    Write-output "Mail verstuurd naar [$($DelegateInfo.userPrincipalName)] met een link naar de OneDrive van gebruiker [$User]."
                                    Write-Log -LogOutput ("Mail verstuurd naar [$($DelegateInfo.userPrincipalName)] met een link naar de OneDrive van gebruiker [$User].") -Path $FilePath  
                                }
                                catch{
                                    Write-output "Het is niet gelukt om een link te sturen van OneDrive [$User] naar [$($DelegateInfo.userPrincipalName)]."
                                    Write-Log -LogOutput ("Geen OneDrive data gevonden voor gebruiker [$User]. $_") -Path $FilePath    
                                }
                            }
                        }else{
                            Write-output "Geen OneDrive data gevonden voor gebruiker [$User]."
                            Write-Log -LogOutput ("Geen OneDrive data gevonden voor gebruiker [$User].") -Path $FilePath                            
                        }
                    }

                    if($global:ErrorCount -eq 0){
                        ###### Start removing licenes ######
                        # First remove from license groups in onpremise or Entra ID
                        if($removeLicenses -eq 0){
                            try{
                                # Get all licenses assigned to user and if it's direct or via group
                                $Uri = "https://graph.microsoft.com/v1.0/users/$($User)/licenseAssignmentStates"
                                $UserLicenses = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method GET).value

                                # Get all license details from license assigned to user
                                $Uri = "https://graph.microsoft.com/v1.0/users/$($User)/licenseDetails"
                                $UserLicensesDetails = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method GET).value

                                $UserLicensesDirect = ($UserLicenses | Where-Object {$null -eq $_.assignedByGroup})
                                $UserLicensesGroup = ($UserLicenses | Where-Object {$null -ne $_.assignedByGroup})

                                # Remove user from direct assigned licenses
                                foreach ($UserLicense in $UserLicensesDirect){
                                    $UserLicenseToRemove = $UserLicensesDetails | Where-Object {$_.skuId -eq $UserLicense.skuId}

                                    $body = @{
                                        addLicenses = @()
                                        removeLicenses= @($($UserLicenseToRemove.skuId))
                                    } | ConvertTo-Json

                                    $uri = 'https://graph.microsoft.com/v1.0/users/{0}/assignLicense' -f $($UserInfo.id)
                                    Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method POST -ContentType "application/json" -Body $body

                                    Write-Output "Licentie [$($UserLicenseToRemove.skuPartNumber)] verwijderd bij gebruiker [$User]."
                                    Write-Log -LogOutput ("Licentie [$($UserLicenseToRemove.skuPartNumber)] verwijderd bij gebruiker [$User].") -Path $FilePath
                                }
                                # Remove user from group assigned licenses
                                foreach ($UserLicense in $UserLicensesGroup){
                                    # Get license group info
                                    $Uri = "https://graph.microsoft.com/v1.0/groups/$($UserLicense.assignedByGroup)?`$select=id,displayName,onPremisesSamAccountName,membershipRule,onPremisesSyncEnabled"
                                    $LicenseGroup = Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method GET

                                    # Check if group is dynamic
                                    if(-not($($LicenseGroup.membershipRule))){ 
                                        # Check if group is onpremise
                                        if($($LicenseGroup.onPremisesSyncEnabled) -eq $true){
                                            Remove-ADGroupMember -Identity $($LicenseGroup.onPremisesSamAccountName) -Members $($UserInfo.onPremisesSamAccountName) -Server $Server -Credential $psCredential -Confirm:$false

                                            Write-Output "Gebruiker [$($UserInfo.userPrincipalName)] verwijderd uit licentie groep [$($LicenseGroup.displayName)] in domein [$Server]."
                                            Write-Log -LogOutput ("Gebruiker [$($UserInfo.userPrincipalName)] verwijderd uit licentie groep [$($LicenseGroup.displayName)] in domein [$Server].") -Path $FilePath                    
                                        }else{
                                            $Uri = "https://graph.microsoft.com/v1.0/groups/$($LicenseGroup.id)/members/$($UserInfo.id)/`$ref"
                                            Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method DELETE -ErrorAction SilentlyContinue

                                            Write-Output "Gebruiker [$($UserInfo.userPrincipalName)] verwijderd uit licentie groep [$($LicenseGroup.displayName)] in tenant [$TenantName]."
                                            Write-Log -LogOutput ("Gebruiker [$($UserInfo.userPrincipalName)] verwijderd uit licentie groep [$($LicenseGroup.displayName)] in tenant [$TenantName].") -Path $FilePath  
                                        }               
                                    }else{
                                        Write-output "Gebruiker [$($UserInfo.userPrincipalName)] kan niet verwijderd worden uit dynamische groep [$($LicenseGroup.displayName)]."
                                        Write-Log -LogOutput ("Gebruiker [$($UserInfo.userPrincipalName)] kan niet verwijderd worden uit dynamische groep [$($LicenseGroup.displayName)].") -Path $FilePath
                                    }
                                }
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om licentie(s) te verwijderen van gebruiker [$User]. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om licentie(s) te verwijderen van gebruiker [$User]. $_"
                            }
                        }
                    }
                }
                else{
                    # Check if user is disabled if not please disable user first before removing
                    if($UserInfo.onPremisesSyncEnabled -eq $true){
                        if($($UserInfo.accountEnabled) -eq $false){
                            # Start removing user account onprem
                            try{
                                Remove-AdUser -Identity $($UserInfo.onPremisesSamAccountName) -Server $Server -Credential $psCredential -Confirm:$false

                                Write-Output "Gebruiker [$User] verwijderd in domein [$Server]."
                                Write-Log -LogOutput ("Gebruiker [$User] verwijderd in domein [$Server].") -Path $FilePath    
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om gebruiker [$User] te verwijderen in domein [$Server]. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om gebruiker [$User] te verwijderen in domein [$Server]. $_"
                            }
                        }else{
                            Write-Output "Gebruiker [$User] is nog actief in domein [$Server]. Schakel gebruiker eerst uit."
                            Write-Log -LogOutput ("Gebruiker [$User] is nog actief in domein [$Server]. Schakel gebruiker eerst uit.") -Path $FilePath   
                        }
                    }else{
                        if($($UserInfo.accountEnabled) -eq $false){
                            # Start removing user account in Entra ID
                            try{
                                $Uri = "https://graph.microsoft.com/v1.0/users/$($UserInfo.id)"
                                Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Delete

                                Write-Output "Gebruiker [$User] verwijderd in tenant [$TenantName]."
                                Write-Log -LogOutput ("Gebruiker [$User] verwijderd in tenant [$TenantName].") -Path $FilePath  
                            }catch{
                                $global:ErrorCount += 1
                                Write-Log -LogOutput ("Het is niet gelukt om gebruiker [$User] te verwijderen in de tenant [$TenantName]. $_") -Path $FilePath   
                                Write-error "Het is niet gelukt om gebruiker [$User] te verwijderen in de tenant [$TenantName]. $_"
                            }
                        }else{
                            Write-Output "Gebruiker [$User] is nog actief in tenant [$TenantName]. Schakel gebruiker eerst uit."
                            Write-Log -LogOutput ("Gebruiker [$User] is nog actief in tenant [$TenantName]. Schakel gebruiker eerst uit.") -Path $FilePath 
                        }
                    }
                }
            }
        }
    }

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