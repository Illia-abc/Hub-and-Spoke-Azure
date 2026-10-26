param location string
param tags object
param adminUsername string 
param sshPublicKey string
param vmSize string

@description('Array of { name, subnetId, asgId } (asgId may be empty)')
param vms array

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for vm in vms: {
  name: 'nic-${vm.name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vm.subnetId }
          applicationSecurityGroups: empty(vm.asgId) ? null : [
            { id: vm.asgId }
          ]
        }
      }
    ]
  }
}]

resource machines 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (vm, i) in vms: {
  name: vm.name
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: vm.name
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
  }
}]
