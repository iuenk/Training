# Sometimes you ugrade a license SKU and need to remove the old one from the group. This script does just that.

# Get SKUs
$Uri = "https://graph.microsoft.com/v1.0/subscribedSkus"
(Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get).Value

# Get group assigned licenses
$Uri = "https://graph.microsoft.com/v1.0/groups/<groupId>/assignedLicenses"
(Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Get).value

# Remove license from group
$Uri = "https://graph.microsoft.com/v1.0/groups/<groupId>/assignLicense"

$Body = @"
{
  "addLicenses": [],
  "removeLicenses": ["<SkuId>"]
}
"@

Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method Post -Body $Body -ContentType "application/json"