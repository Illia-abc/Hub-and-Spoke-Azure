using 'main.bicep'

param location = 'polandcentral'

param tags = {
  project: 'hub-spoke'
  owner: 'illia'
  env: 'lab'
  purpose: 'Pet-Project'
}

// Desired state lives in git: change a switch in a PR, review the what-if, merge to deploy.
// Phase 1: compute only -> Phase 2: firewall/bastion (paid) -> Phase 3: policy
param deployCompute = true
param deployFirewall = true
param deployBastion = true
param deployPolicy = true

param adminUsername = 'azureuser'
// PowerShell: $env:SSH_PUBLIC_KEY = (Get-Content ~/.ssh/id_ed25519.pub)   (set it BEFORE running az deployment)
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
param vmSize = 'Standard_B2ats_v2'
