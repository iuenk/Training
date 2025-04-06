#=============================================================================================================================
#
# Script Name:     AppCreateMailbox.ps1
# Description:     Create a shared, room or equipment mailbox.
#   
# Notes      :     
#
# Created by :     Ivo Uenk
# Date       :     3-7-2024
# Version    :     1.0
#=============================================================================================================================

Param (
  [string] $CustomerId,
  [string] $Name,
  [string] $Type,
  [string] $RespondersEmail,
  [string] $EmailAddress
)

#. .\AppRunEnv.ps1
. .\AppMail.ps1
. .\AppAuthHeader.ps1
. .\AppTestAllowedUser.ps1
. .\AppRetryCmdlet.ps1
. .\AppWriteLog.ps1

################## Variables ##################

$File = "Aanmaken-Mailbox" + "-" + "$Type" + "-" + ((Get-Date).ToString("dd-MM-yyyy-HHmm"))
$FilePath = $env:TEMP + "\" + $File + ".log"
$SelfServiceGroup = Get-AutomationVariable -Name "SelfServiceGroup"

$MailSender = Get-AutomationVariable -Name "EmailAutomation"
$Recipient = $RespondersEmail
$Recipients = $Recipient.Split(",")
$RecipientCC = Get-AutomationVariable -Name "EmailSupport"
$RecipientsCC = $RecipientCC.Split(",")

##################  Prerequisties ##################

# Get credentials
$AutomationCredential = Get-AutomationPSCredential -Name "LangoCreds"
$userName = $AutomationCredential.UserName  
$securePassword = $AutomationCredential.Password
$psCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userName, $securePassword

##################  Main logic ##################

$global:ErrorCount = 0
$TestUser = Test-AllowedUser -UserPrincipalName $RespondersEmail -GroupName $SelfServiceGroup

if($TestUser){
    # Strip EmailAddress to get domain
    $findchar = $EmailAddress.IndexOf("@")
    $EmailDomain = $EmailAddress.Substring($findchar+1)

    # Get allowed custom domains tenant
    $verifiedDomains = @()
    $uri = "https://graph.microsoft.com/v1.0/domains"
    $customDomains = ((Invoke-RestMethod -Uri $uri -Headers $($global:authHeader) -Method Get).value | Select-Object id,isVerified)

    foreach($domain in $customDomains){
        if($domain.isVerified -eq $true){
            $verifiedDomains += $domain.id
        }
    }

    if($EmailDomain -in $verifiedDomains){
    }else{
        $global:ErrorCount += 1
        Write-Log -LogOutput ("Het opgegeven domein [$EmailDomain] is niet bekend in Custom Domains.") -Path $FilePath
        Write-Error "Het opgegeven domein [$EmailDomain] is niet bekend in Custom Domains."
    }

    if($global:ErrorCount -eq 0){
        try{
            Connect-ExchangeOnline -Credential $psCredential -WarningAction Ignore
            Write-output "[$userName] verbonden met Exchange Online."
        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Verbinding naar Exchange Online mislukt met automation account [$userName]. $_") -Path $FilePath   
            Write-Error "Verbinding naar Exchange Online mislukt met automation account [$userName]. $_"
        }
    }

    if($global:ErrorCount -eq 0){
        # Aanmaken nieuwe mailbox met opties
        $Mailbox = Get-Mailbox -Identity $EmailAddress

        if(-not($Mailbox)){
            $DisplayName = $Name
            $Name = "mb_$($DisplayName.Replace(' ','').Replace('&','').Replace('(','').Replace(')','').ToLower().trim())"
            $EmailAddress = $EmailAddress.trim()
                    
            $Params = @{
                DisplayName = $DisplayName
                Name = $Name 
                PrimarySmtpAddress = $EmailAddress
                ErrorAction = 'Stop'
            }

            if($Type -like 'Shared*'){$Params.add("Shared",$true)}
            if($Type -like 'Room*'){$Params.add("Room",$true)}
            if($Type -like 'Equipment*'){$Params.add("Equipment",$true)}

            New-Mailbox @Params
            Write-output "Mailbox [$Type] met [$DisplayName] is aangemaakt."
            Write-Log -LogOutput ("Mailbox [$Type] met [$DisplayName] is aangemaakt.") -Path $FilePath

            # Aanmaken distributiegroep voor mailbox
            $DistributionGroup = Get-DistributionGroup -Identity "role_$($name)"

            if(-not($DistributionGroup)){
                new-DistributionGroup -Name "role_$($name)" -Type Security -ErrorAction Stop
                Write-output "DistributionGroup [role_$($name)] is aangemaakt."
                Write-Log -LogOutput ("DistributionGroup [role_$($name)] is aangemaakt.") -Path $FilePath
            }
            else{
                Write-output "DistributionGroup [role_$($name)] bestaat al."
                Write-Log -LogOutput ("DistributionGroup [role_$($name)] bestaat al.") -Path $FilePath
            }

            Set-DistributionGroup -Identity "role_$($name)" -HiddenFromAddressListsEnabled $true -ErrorAction Stop
            Add-MailboxPermission -identity $Name -User "role_$($name)" -AccessRights FullAccess -ErrorAction Stop
            Add-RecipientPermission -identity $Name -trustee "role_$($name)" -AccessRights SendAs -confirm:$false -ErrorAction Stop
            Write-output "Groep [role_$($name)] rechten gegeven op Mailbox [$name]."
            Write-Log -LogOutput ("Groep [role_$($name)] rechten gegeven op Mailbox [$name].") -Path $FilePath
            
            if(($Type -notlike 'Equipment*') -and ($Type -notlike 'Room*')){
                Set-Mailbox -Identity $Name -MessageCopyForSentAsEnabled $true -MessageCopyForSendOnBehalfEnabled $true -ErrorAction Stop
            }
            Write-output "Mailbox [$Type] [$DisplayName] opties geactiveerd: MessageCopyForSentAsEnabled,MessageCopyForSendOnBehalfEnabled." 
            Write-Log -LogOutput ("Mailbox [$Type] [$DisplayName] opties geactiveerd: MessageCopyForSentAsEnabled,MessageCopyForSendOnBehalfEnabled.") -Path $FilePath
        }
        else{
            Write-output "Mailbox [$Type] met [$DisplayName] bestaat al."
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

    try{
        Invoke-RetryCmdlet -Cmdlet {$null = Disconnect-ExchangeOnline -Confirm:$false}
        Write-output "Verbinding external services verbreken."
        
    }catch {} 
}
else{
    $Subject = "Selfservice [$File] door [$RespondersEmail] niet gemachtigd"
    $Body = "Gebruiker [$RespondersEmail] heeft via Selfservice een [$File] uitgevoerd [$CustomerId]. Deze gebruiker is niet geauthoriseerd voor deze actie."
    Send-Mail -Recipients $Recipients -Recipientscc $RecipientsCC -Subject $Subject -Body $Body -MailSender $MailSender
    Write-output "Email verstuurd aan [$Recipients][$RecipientsCC]" 
}