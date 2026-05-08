# Get all Device platform scripts in Intune and save them to a local folder. 
$TenantId = "<tenantId>"
$AppID = "<appId>" # Service Principal with delegated Graph API Permissions: User.Read.All, Group.Read.All, Directory.Read.All etc.

#GraphAccessToken
$Scope = "https://graph.microsoft.com/.default"
$Token = Get-MsalToken -ClientId $AppID -TenantId $TenantId -scope $Scope -Interactive

$authHeader = @{
    'Authorization' = $token.CreateAuthorizationHeader()
}

$FolderPath = "<folderPath>" # specify the local folder path where you want to save the scripts
$FileName = $null # if you want to download all scripts set this to $null otherwise specify the file name of the script you want to download for example "Script1.ps1"

$Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts"
$result = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method GET

if ($FileName){
    $scriptId = $result.value | Select-Object id,fileName | Where-Object -Property fileName -eq $FileName
    $script = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($scriptId.id)" -Headers $authHeader -Method GET
    [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($script.scriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $FolderPath $($script.fileName))
}
else{
    $scriptIds = $result.value | Select-Object id,fileName
    foreach($scriptId in $scriptIds){
        $script = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($scriptId.id)" -Headers $authHeader -Method GET
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($script.scriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $FolderPath $($script.fileName))
    }
}

$Uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
$result = Invoke-RestMethod -Uri $Uri -Headers $authHeader -Method GET

if ($FileName){
    $scriptId = $result.value | Select-Object id,fileName | Where-Object -Property fileName -eq $FileName
    $script = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$($scriptId.id)" -Headers $authHeader -Method GET
    [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($script.detectionScriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $FolderPath $(($script.displayName).Replace("|","") + ".ps1"))
}
else{
    $scriptIds = $result.value | Select-Object id,fileName
    foreach($scriptId in $scriptIds){
        $script = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$($scriptId.id)" -Headers $authHeader -Method GET
        [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($($script.detectionScriptContent))) | Out-File -Encoding ASCII -FilePath $(Join-Path $FolderPath $(($script.displayName).Replace("|","") + ".ps1"))
    }
}