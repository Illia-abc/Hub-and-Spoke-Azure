param(
    [Parameter(Mandatory)][string]$Owner,
    [Parameter(Mandatory)][string]$Repo,

    # New GitHub repositories put two numeric IDs into the OIDC subject:
    #   repo:<owner>@<ownerId>/<repo>@<repoId>:pull_request
    # Entra compares the subject character by character, so a credential without
    # the IDs never matches (AADSTS700213). Leave both empty to read them from GitHub.
    [string]$OwnerId,
    [string]$RepoId,

    # 'Ids'   = repo:OWNER@OWNER_ID/REPO@REPO_ID:...  (repositories created after 15 July 2026)
    # 'Names' = repo:OWNER/REPO:...                   (older repositories that did not opt in)
    [ValidateSet('Ids', 'Names')][string]$SubjectFormat = 'Ids'
)

$ErrorActionPreference = 'Stop'   # stop on any PowerShell error

# PowerShell 5.1 does not stop when az fails, so we check the exit code after every az call.
function Check { if ($LASTEXITCODE -ne 0) { throw "az command failed (exit code $LASTEXITCODE)" } }

$RG       = 'rg-hubspoke-lab'
$Location = 'polandcentral'
$AppName  = 'sp-github-hubspoke'
$Issuer   = 'https://token.actions.githubusercontent.com'

$SubId    = az account show --query id -o tsv;       Check
$TenantId = az account show --query tenantId -o tsv; Check

# 0. Numeric IDs of the GitHub owner and repository (public repositories need no token)
if ($SubjectFormat -eq 'Ids' -and (-not $OwnerId -or -not $RepoId)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   # needed on PowerShell 5.1
    $headers = @{ 'User-Agent' = 'bootstrap-script'; 'Accept' = 'application/vnd.github+json' }

    # A private repository needs a token: $env:GITHUB_TOKEN or an authenticated gh CLI
    $token = $env:GITHUB_TOKEN
    if (-not $token -and (Get-Command gh -ErrorAction SilentlyContinue)) { $token = (gh auth token 2>$null) }
    if ($token) { $headers['Authorization'] = "Bearer $token" }

    try {
        $info = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo" -Headers $headers
    }
    catch {
        throw "Could not read $Owner/$Repo from the GitHub API: $($_.Exception.Message). Check the names, or pass -OwnerId and -RepoId by hand."
    }
    if (-not $OwnerId) { $OwnerId = [string]$info.owner.id }
    if (-not $RepoId)  { $RepoId  = [string]$info.id }
}

if ($SubjectFormat -eq 'Ids') { $Prefix = "repo:$Owner@$OwnerId/$Repo@$RepoId" }
else                          { $Prefix = "repo:$Owner/$Repo" }

# 1. Resource group
az group create --name $RG --location $Location --output none `
    --tags project=hub-spoke owner=illia env=lab deployment=bicep purpose=Pet-Project
Check

# 2. Identity for GitHub Actions (reuse it if the script was already run)
$count = az ad app list --display-name $AppName --query "length(@)" -o tsv; Check
if ([int]$count -gt 1) { Write-Warning "$count app registrations are named '$AppName'. Using the first one; delete the extra ones in Entra ID." }

$AppId = az ad app list --display-name $AppName --query "[0].appId" -o tsv; Check
if (-not $AppId) { $AppId = az ad app create --display-name $AppName --query appId -o tsv; Check }

$SpId = az ad sp list --filter "appId eq '$AppId'" --query "[0].id" -o tsv; Check
if (-not $SpId) { $SpId = az ad sp create --id $AppId --query id -o tsv; Check }

# 3. Trust this GitHub repo (OIDC, no password): one credential per way a job can start.
#    NOTE: "${Prefix}:..." needs the braces. "$Prefix:environment" would be read as a scoped variable.
$subjects = [ordered]@{
    'gh-environment-lab' = "${Prefix}:environment:lab"        # deploy: apply job
    'gh-branch-main'     = "${Prefix}:ref:refs/heads/main"    # deploy: plan job
    'gh-pull-request'    = "${Prefix}:pull_request"           # validate: what-if job
}

$existing = @(az ad app federated-credential list --id $AppId --query "[].name" -o tsv); Check
foreach ($name in $subjects.Keys) {
    $json = @{
        name      = $name
        issuer    = $Issuer
        subject   = $subjects[$name]
        audiences = @('api://AzureADTokenExchange')
    } | ConvertTo-Json -Compress

    $file = New-TemporaryFile
    [System.IO.File]::WriteAllText($file.FullName, $json)

    if ($existing -contains $name) {
        az ad app federated-credential update --id $AppId --federated-credential-id $name --parameters "@$($file.FullName)" --output none
    }
    else {
        az ad app federated-credential create --id $AppId --parameters "@$($file.FullName)" --output none
    }
    Check
    Remove-Item $file
}

# 4. Rights on THIS resource group only
$Scope = "/subscriptions/$SubId/resourceGroups/$RG"
foreach ($role in 'Contributor', 'Resource Policy Contributor') {
    $has = az role assignment list --assignee $SpId --scope $Scope --query "[?roleDefinitionName=='$role'] | length(@)" -o tsv; Check
    if ([int]$has -eq 0) {
        az role assignment create --assignee-object-id $SpId --assignee-principal-type ServicePrincipal `
            --role $role --scope $Scope --output none
        Check
    }
}

# 5. Values for GitHub secrets, and proof of what was trusted
Write-Host ""
Write-Host "GitHub secrets (Settings > Secrets and variables > Actions):"
Write-Host "AZURE_CLIENT_ID       = $AppId"
Write-Host "AZURE_TENANT_ID       = $TenantId"
Write-Host "AZURE_SUBSCRIPTION_ID = $SubId"
Write-Host ""
Write-Host "Federated credentials (subject must be identical to the one in the token):"
foreach ($name in $subjects.Keys) { Write-Host ("  {0,-20} {1}" -f $name, $subjects[$name]) }
if ($SubjectFormat -eq 'Ids') {
    Write-Host ""
    Write-Host "GitHub IDs used: owner = $OwnerId, repository = $RepoId"
}