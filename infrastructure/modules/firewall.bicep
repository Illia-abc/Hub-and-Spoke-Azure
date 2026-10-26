// Azure Firewall (Basic) + policy + rules + diagnostics
param location string
param tags object
param hubVnetName string
param workspaceId string

param devAddressSpace string = '10.1.0.0/16'
param prodAddressSpace string = '10.2.0.0/16'

@description('FQDNs allowed for OS updates')
param ubuntuFqdns array = [
  'azure.archive.ubuntu.com'
  'security.ubuntu.com'
]

// ---------- Public IPs ----------
resource pipFw 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-afw-hub'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource pipMgmt 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-afw-mgmt'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// ---------- Policy (deny by default; only listed rules allow) ----------
resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: 'afwp-hub'
  location: location
  tags: tags
  properties: {
    sku: { tier: 'Basic' }
  }
}

resource networkGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'net-rules'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'dev-to-prod-web'
            ipProtocols: ['TCP']
            sourceAddresses: [devAddressSpace]
            destinationAddresses: [prodAddressSpace]
            destinationPorts: ['80', '443']
          }
        ]
      }
    ]
  }
}

resource appGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'DefaultApplicationRuleCollectionGroup'
  dependsOn: [networkGroup] // groups in one policy must be deployed sequentially
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'app-rules'
        priority: 200
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'ubuntu-updates'
            sourceAddresses: [devAddressSpace, prodAddressSpace]
            protocols: [
              { protocolType: 'Http', port: 80 }
              { protocolType: 'Https', port: 443 }
            ]
            targetFqdns: ubuntuFqdns
          }
        ]
      }
    ]
  }
}

// ---------- Firewall ----------
resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'afw-hub'
  location: location
  tags: tags
  dependsOn: [appGroup]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    firewallPolicy: { id: policy.id }
    ipConfigurations: [
      {
        name: 'ipconfig-fw'
        properties: {
          subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnetName, 'AzureFirewallSubnet') }
          publicIPAddress: { id: pipFw.id }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'ipconfig-mgmt'
      properties: {
        subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnetName, 'AzureFirewallManagementSubnet') }
        publicIPAddress: { id: pipMgmt.id }
      }
    }
  }
}

// ---------- Diagnostics -> Log Analytics (resource-specific tables) ----------
resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-afw-to-law'
  scope: firewall
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
