#Exchange Online:
New-OwaMailboxPolicy -Name "Ucorp | OWA | Prohibit Download"
Set-OwaMailboxPolicy -Identity "Ucorp | OWA | Prohibit Download" -ConditionalAccessPolicy ReadOnly

# Configure owa mailbox policy for a specific user
CasMailbox -Identity "username@ucorp.nl" -OwaMailboxPolicy "Ucorp | OWA | Prohibit Download"

# Configure owa mailbox policy for all users
Get-Mailbox | Set-CASMailbox -OwaMailboxPolicy "Ucorp | OWA | Prohibit Download"

# SharePoint Online:
Connect-SPOService -Url https://tenantname-admin.sharepoint.com

# List all sites en show conditional accesss status
Get-SPOSite | ForEach-Object { Get-SPOSite -Detailed -Identity $_.URL | Select-Object Url,Conditional* }

# Set AllowLimitedAccess for a specific site
Set-SPOSite -Identity https://tenantname.sharepoint.com/sites/sitename -ConditionalAccessPolicy AllowLimitedAccess

# Set conditional access for all sites
$sites = Get-SPOSite -Limit all -Filter "Url -like 'tenantname.sharepoint.com/sites'"
Foreach($site in $sites){Set-SPOSite -identity $site -ConditionalAccessPolicy AllowLimitedAccess}

# Set AllowLimitedAccess for whole tenant
Set-SPOTenant -ConditionalAccessPolicy AllowLimitedAccess

# Set conditional access for one person
Set-SPOSite -Identity https://tenantname-my.sharepoint.com/personal/firstname_lastname_domain_nl -ConditionalAccessPolicy AllowLimitedAccess

# Set conditional access for all personal sites
$personalsites = Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Url -like '-my.sharepoint.com/personal/'"
Foreach($site in $personalsites){Set-SPOSite -identity $site -ConditionalAccessPolicy AllowLimitedAccess}