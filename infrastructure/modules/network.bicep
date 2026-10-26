param location string 
param tags object

var hubVirtualNetworkName = 'vnet-hub'
var firewallSubnetName = 'AzureFirewallSubnet'
var BastonSubnetName = 'AzureBastionSubnet'
var FirewallMgmtSubnetName = 'AzureFirewallManagementSubnet'

var devVirtualNetworkName = 'vnet-dev'
var devSubnetVnetName = 'snet-dev-workload'

var prodVirtualNetworkName = 'vnet-prod'
var prodSubnetVnetName = 'snet-prod-web'

param hubAddressSpace string = '10.0.0.0/22'
param devAddressSpace string = '10.1.0.0/16'
param prodAddressSpace string = '10.2.0.0/16'
param firewallSubnetPrefix string = '10.0.0.0/26'
param bastionSubnetPrefix string = '10.0.0.64/26'
param firewallMgmtSubnetPrefix string = '10.0.0.128/26'
param devSubnetPrefix string = '10.1.1.0/24'
param prodSubnetPrefix string = '10.2.1.0/24'

param devRouteTableId string
param prodRouteTableId string

// ---------- ASG ----------
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-web'
  location: location
  tags: tags
}

// ---------- NSGs ----------
resource nsgDev 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-dev'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-bastion-ssh'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgProd 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-prod'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-dev-web'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: devAddressSpace
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [{ id: asgWeb.id }]
          destinationPortRanges: ['80', '443']
        }
      }
      {
        name: 'allow-bastion-ssh'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange:  '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------- VNets ----------
resource vnetHub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVirtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [hubAddressSpace]
    }
    subnets: [
      {
        name: firewallSubnetName
        properties: {addressPrefixes: [firewallSubnetPrefix]}
      }
      {
        name: BastonSubnetName
        properties: {addressPrefixes: [bastionSubnetPrefix]}
      }
      {
        name: FirewallMgmtSubnetName
        properties:{addressPrefixes: [firewallMgmtSubnetPrefix]}  
      }
    ]
  } 
}

resource vnetDev 'Microsoft.Network/virtualNetworks@2024-05-01' = { 
  name: devVirtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [devAddressSpace]
    }
    subnets: [
      {
        name: devSubnetVnetName
        properties: {
          addressPrefix: devSubnetPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: { id: nsgDev.id }
          routeTable: { id: devRouteTableId }
        }
      }
    ]
  } 
}

resource vnetProd 'Microsoft.Network/virtualNetworks@2024-05-01' = { 
  name: prodVirtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [prodAddressSpace]
    }
    subnets: [
      {
        name: prodSubnetVnetName
        properties: {
          addressPrefix: prodSubnetPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: { id: nsgProd.id }
          routeTable: { id: prodRouteTableId }
        }
      }
    ]
  } 
}

// ---------- Peerings (hub <-> dev, hub <-> prod; NO dev <-> prod) ----------
var peeringProps = {
  allowVirtualNetworkAccess: true
  allowForwardedTraffic: true
  allowGatewayTransit: false
  useRemoteGateways: false
}

resource hubToDev 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: vnetHub
  name: 'hub-to-dev'
  properties: union(peeringProps, { 
    remoteVirtualNetwork: { 
      id: vnetDev.id 
    } 
  })
}

resource devToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01'= {
  parent: vnetDev
  name: 'dev-to-hub'
  properties: union(peeringProps, { 
    remoteVirtualNetwork: { 
      id: vnetHub.id 
    } 
  })
}

resource hubToProd 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01'= {
  parent: vnetHub
  name: 'hub-to-prod'
  dependsOn: [hubToDev] // peerings on the same VNet are created one at a time
  properties: union(peeringProps, { 
    remoteVirtualNetwork: { 
      id: vnetProd.id 
    } 
  })
}

resource prodToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01'= {
  parent: vnetProd
  name: 'prod-to-hub'
  properties: union(peeringProps, { 
    remoteVirtualNetwork: { 
      id: vnetHub.id 
    } 
  })
}

output hubVnetName string = vnetHub.name
output devSubnetId string = '${vnetDev.id}/subnets/snet-dev-workload'
output prodSubnetId string = '${vnetProd.id}/subnets/snet-prod-web'
output asgWebId string = asgWeb.id
