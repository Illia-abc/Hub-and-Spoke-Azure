param location string
param tags object
param hubVirtualNetworkName string

// Public IP address for Azure Bastion
resource pipBastion 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-bas-hub'
  location: location
  tags: tags
  sku: { name: 'Standard' } // Standard SKU for Bastion
  properties: { publicIPAllocationMethod: 'Static' } // IP address remains unchanged
}

// Azure Bastion provides secure access to virtual machines
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bas-hub'
  location: location
  tags: tags
  sku: {name: 'Basic'}
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig-bastion' // Network configuration name  
        properties: {
          // Connect Bastion to the dedicated subnet in the Hub VNet
          subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVirtualNetworkName, 'AzureBastionSubnet') } 
          publicIPAddress: { id: pipBastion.id } // Assign the public IP address to Bastion
        }
      }
    ]
  }
}
