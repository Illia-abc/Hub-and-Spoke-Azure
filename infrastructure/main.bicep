// Azure Hub-and-Spoke lab. Deploy at resource-group scope:
//   az deployment group create -g rg-hubspoke-lab -f main.bicep -p main.bicepparam
targetScope = 'resourceGroup'

param location string = 'polandcentral'

@description('Base tags; the "deployment" tag is added automatically as "bicep"')
param tags object

// ---------- Phase switches ----------
@description('Phase 1: test VMs')
param deployCompute bool = true
@description('Phase 2 (paid): Azure Firewall + routes to it')
param deployFirewall bool = false
@description('Phase 2 (paid): Azure Bastion')
param deployBastion bool = false
@description('Phase 3: Azure Policy assignments')
param deployPolicy bool = false

// ---------- VM settings ----------
param adminUsername string = 'azureuser'
@description('SSH public key (Ed25519), e.g. contents of ~/.ssh/id_ed25519.pub')
param sshPublicKey string
param vmSize string = 'Standard_B2ats_v2'

// ---------- Address plan ----------
param firewallPrivateIp string = '10.0.0.4'

var allTags = union(tags, { deployment: 'bicep' })

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: allTags
  }
}

module routing 'modules/routing.bicep' = {
  name: 'routing'
  params: {
    location: location
    tags: allTags
    firewallPrivateIp: firewallPrivateIp
    enableDefaultRoute: deployFirewall
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: allTags
    devRouteTableId: routing.outputs.devRouteTableId
    prodRouteTableId: routing.outputs.prodRouteTableId
  }
}

module compute 'modules/compute.bicep' = if (deployCompute) {
  name: 'compute'
  params: {
    location: location
    tags: allTags
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    vms: [
      {
        name: 'vm-dev-01'
        subnetId: network.outputs.devSubnetId
        asgId: ''
      }
      {
        name: 'vm-prod-01'
        subnetId: network.outputs.prodSubnetId
        asgId: network.outputs.asgWebId
      }
    ]
  }
}

module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'firewall'
  params: {
    location: location
    tags: allTags
    hubVnetName: network.outputs.hubVnetName
    workspaceId: monitoring.outputs.workspaceId
  }
}

module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion'
  params: {
    location: location
    tags: allTags
    hubVirtualNetworkName: network.outputs.hubVnetName
  }
}

// Policy goes last so it cannot block the deployment itself
module policy 'modules/policy.bicep' = if (deployPolicy) {
  name: 'policy'
  dependsOn: [
    compute
    firewall
    bastion
  ]
}

output firewallPrivateIpActual string = firewall.?outputs.privateIp ?? 'not deployed'
output firewallPrivateIpExpectedByRoutes string = firewallPrivateIp
