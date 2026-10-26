// Route tables for the spokes: 0.0.0.0/0 -> Azure Firewall private IP.
// Created BEFORE the network module (subnets reference them), so the
// Firewall IP is a parameter (first usable IP of AzureFirewallSubnet = x.x.x.4).
param location string
param tags object

@description('Private IP of Azure Firewall (first usable address of AzureFirewallSubnet)')
param firewallPrivateIp string = '10.0.0.4'

@description('Add the default route only when the Firewall exists, otherwise traffic would be black-holed')
param enableDefaultRoute bool

var routes = enableDefaultRoute ? [
  {
    name: 'default-to-firewall'
    properties: {
      addressPrefix: '0.0.0.0/0'
      nextHopType: 'VirtualAppliance'
      nextHopIpAddress: firewallPrivateIp
    }
  }
] : []

resource rtDev 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-dev'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: routes
  }
}

resource rtProd 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-prod'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: true
    routes: routes
  }
}

output devRouteTableId string = rtDev.id
output prodRouteTableId string = rtProd.id
