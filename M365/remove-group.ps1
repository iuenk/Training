#=============================================================================================================================
#
# Script Name:     remove-group.ps1
# Description:     Remove security group onpremise and in the cloud and distribution group.
#   
# Notes      :     It's not possible to remove Microsoft 365 Groups that are used with SharePoint. Can have a major impact
#                  when those groups are removed. 
#
# Created by :     Ivo Uenk
# Date       :     3-7-2024
# Version    :     1.0
#=============================================================================================================================

Param (
  [string] $CustomerId,
  [string] $GroupName,
  [string] $RespondersEmail
)

#. .\AppRunEnv.ps1
. .\AppMail.ps1
. .\AppAuthHeader.ps1
. .\AppTestAllowedUser.ps1
. .\AppRetryCmdlet.ps1
. .\AppWriteLog.ps1

################## Variables ##################

$File = "Verwijderen-Groep" + "-" + "$Type" + "-" + ((Get-Date).ToString("dd-MM-yyyy-HHmm"))
$FilePath = $env:TEMP + "\" + $File + ".log"
$SelfServiceGroup = Get-AutomationVariable -Name "SelfServiceGroup"

$MailSender = Get-AutomationVariable -Name "EmailAutomation"
$Recipient = $RespondersEmail
$Recipients = $Recipient.Split(",")
$RecipientCC = Get-AutomationVariable -Name "EmailSupport"
$RecipientsCC = $RecipientCC.Split(",")

$TenantName = Get-AutomationVariable -Name "TenantName"
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

    # Check if group is onprem or cloud
    $Uri = "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(displayName,'$GroupName')"
    $Group = (Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method Get).value

    if($($Group.onPremisesSyncEnabled) -eq "true"){
        try {
            Remove-ADGroup -Identity $($Group.displayName) -Server $Server -Credential $psCredential -Confirm:$false

            Write-output "Groep [$GroupName] is verwijderd uit domein [$Server]."
            Write-Log -LogOutput ("Groep [$GroupName] is verwijderd uit domein [$Server].") -Path $FilePath

        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Het is niet gelukt om groep [$GroupName] te verwijderen uit domein [$Server]. $_") -Path $FilePath   
            Write-error "Het is niet gelukt om groep [$GroupName] te verwijderen uit domein [$Server]. $_"
        }
    }
    else {
        try {
            $Uri = "https://graph.microsoft.com/v1.0/groups/$($Group.id)"
            Invoke-RestMethod -Uri $Uri -Headers $($global:authHeader) -Method DELETE

            Write-output "Groep [$GroupName] is verwijderd in de tenant [$TenantName]."
            Write-Log -LogOutput ("Groep [$GroupName] is verwijderd in de tenant [$TenantName].") -Path $FilePath

        }catch{
            $global:ErrorCount += 1
            Write-Log -LogOutput ("Het is niet gelukt om groep [$GroupName] te verwijderen uit de tenant [$TenantName]. $_") -Path $FilePath   
            Write-error "Het is niet gelukt om groep [$GroupName] te verwijderen uit de tenant [$TenantName]. $_"
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