# One-time setup. Run once, by hand, before the pipeline exists.
# Usage: ./scripts/bootstrap.ps1 -Owner <github-user> -Repo <repo-name>

# Neсessarily parameters, if not provided, the program will stop.
param(
    [Parameter(Mandatory)][string]$Owner, 
    [Parameter(Mandatory)][string]$Repo 
)

$ErrorActionPreference = 'STOP' # This will stop the program if a problem occurs

# PowerShell 5.1 does not stop when az fails, so we check the exit code after every az call.
function Check { if ($LASTEXITCODE -ne 0) { throw "az command failed (exit code $LASTEXITCODE)" } }

# $PSNativeCommandUseErrorActionPreference = $true # PowerShell 7.3+: stop when az fails (We need the STOP rule to work for commands on Azure as well)

$RG = 'rg-hubspoke-lab'
$Location = 'polandcentral'
$SubId = az account show --query id -o tsv
$TenantId = az account show --query tenantId -o tsv

# 1. Resource group create
az group create --name $RG --location $Location --output none --tags project=hub-spoke owner=illia env=lab deployment=bicep purpose=Pet-Project
Check

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create resource group."
}

# 2. Identity for GitHub Action
$AppId = az ad app create --display-name sp-github-hubspoke --query appId -o tsv
Check
$SpId = az ad sp create --id $AppId --query id -o tsv
Check

# 3. Trust this GitHub repo (OIDC, no password): one credential per way a job can start
$subjects = @{
    'gh-environment-lab' = "repo:$Owner/${Repo}:environment:lab"        # deploy: apply job
    'gh-branch-main'     = "repo:$Owner/${Repo}:ref:refs/heads/main"    # deploy: plan job
    'gh-pull-request'    = "repo:$Owner/${Repo}:pull_request"           # validate: what-if job
}   
foreach ($name in $subjects.Keys) {
       $json = @{ name = $name; issuer = 'https://token.actions.githubusercontent.com'
               subject = $subjects[$name]; audiences = @('api://AzureADTokenExchange') } | ConvertTo-Json -Compress
    $file = New-TemporaryFile
    [System.IO.File]::WriteAllText($file.FullName, $json)
    az ad app federated-credential create --id $AppId --parameters "@$($file.FullName)" --output none
    Check
    Remove-Item $file
}

# 4. Rights on THIS resource group only
$Scope = "/subscriptions/$SubId/resourceGroups/$Rg"
foreach ($role in 'Contributor', 'Resource Policy Contributor') {
    az role assignment create --assignee-object-id $SpId --assignee-principal-type ServicePrincipal `
        --role $role --scope $Scope --output none
    Check
}
 
# 5. Values for GitHub secrets
Write-Host "AZURE_CLIENT_ID       = $AppId"
Write-Host "AZURE_TENANT_ID       = $TenantId"
Write-Host "AZURE_SUBSCRIPTION_ID = $SubId"