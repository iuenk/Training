<#PSScriptInfo
.VERSION 1.1
.AUTHOR Ivo Uenk
.RELEASENOTES

#>
<#
.SYNOPSIS
  Disable all shared mailbox user accounts
.DESCRIPTION
  Disable all shared mailbox user accounts
.NOTES
  Version:        1.1
  Author:         Ivo Uenk
  Creation Date:  2025-04-02
  Purpose/Change: Disable all shared mailbox user accounts

  Install the following modules:
  AzureAD
  ExchangeOnlineManagement

#>

Import-Module 'AzAccount'
Import-Module 'ExchangeOnlineManagement'

# Get the credential from Automation  
$credential = Get-AutomationPSCredential -Name 'AutomationCredentials'  
$userName = $credential.UserName  
$securePassword = $credential.Password

$psCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $userName, $securePassword

# Connect to Microsoft 365 Services
Connect-AzAccount -Credential $psCredential
Connect-ExchangeOnline -Credential $psCredential

# Get all shared mailbox
$allmb = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

# Get all active user objects shared mailbox
$users = $allmb | ForEach-Object {Get-AzADUser -Select AccountEnabled -AppendSelected -Mail $($_.PrimarySmtpAddress) | `
Select-Object UserPrincipalName, Mail, AccountEnabled}

# Set shared mailbox user object in Azure AD to disabled to prevent direct logon
$users | ForEach-Object {Set-AzADUser -UserPrincipalName $_.UserPrincipalName -AccountEnabled $false}