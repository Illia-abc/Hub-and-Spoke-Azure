// Azure Policy assignments at resource group scope (built-in definitions, effect: Deny)
param tagName string = 'env'
param allowedLocations array = ['polandcentral']

// Built-in policy definition IDs
var denyNicPublicIpId = '/providers/Microsoft.Authorization/policyDefinitions/83a86a26-fd1f-447c-b59d-e51f44264114'
var requireTagId = '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
var allowedLocationsId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'

resource denyNicPublicIp 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'deny-nic-public-ips'
  properties: {
    displayName: 'Network interfaces should not have public IPs'
    policyDefinitionId: denyNicPublicIpId
    enforcementMode: 'Default'
  }
}

resource requireEnvTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'require-env-tag'
  properties: {
    displayName: 'Require a tag on resources: ${tagName}'
    policyDefinitionId: requireTagId
    enforcementMode: 'Default'
    parameters: {
      tagName: { value: tagName }
    }
  }
}

resource allowedLocs 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'allowed-locations-poland'
  properties: {
    displayName: 'Allowed locations'
    policyDefinitionId: allowedLocationsId
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: { value: allowedLocations }
    }
  }
}
