// Global parameters
param environmentType string
param location string

// Local parameters exposed to top level
@description('The name of the Managed Cluster resource.')
param clusterName string

@description('AKS service principal used by AKS.  Must have pull rights on <own> dev ACR registry.')
param aksClientId string

@description('Service principal secret/password')
param aksClientSecret string

@description('Optional DNS prefix to use with hosted Kubernetes API server FQDN.')
param dnsPrefix string

@description('Disk size (in GB) to provision for each of the agent pool nodes. This value ranges from 0 to 1023. Specifying 0 will apply the default disk size for that agentVMSize.')
@minValue(0)
@maxValue(1023)
param osDiskSizeGB int

@description('The number of nodes for the cluster.')
@minValue(1)
@maxValue(50)
param agentCount int

@description('The size of the Virtual Machine.')
param agentVMSize string

@description('User name for the Linux Virtual Machines.')
param linuxAdminUsername string

@description('Configure all linux machines with the SSH RSA public key string. Your key should include three parts, for example \'ssh-rsa AAAAB...snip...UcyupgH azureuser@linuxvm\'')
param sshRSAPublicKey string

@description('Name of iactest storage account including unique suffix')
param storageAccountNamePrefix string

@minLength(3)
@maxLength(63)
@description('Name of file share.  Must be between 3 and 63 characters long.')
param fileShareName string

@allowed([
  'SMB'
  'NFS'
])
@description('Conditional IoT deployment.  Must be yes or no.')
param fileShareType string

@description('VNet name')
param vnetName string = 'iactest-vnet'

@description('Address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet Prefix')
param subnetPrefix string = '10.0.0.0/24'

@description('Subnet Name')
param subnetName string = 'iactest-snet'

@description('List of service endpoints to be enabled on subnet' )
param serviceEndpoints array = [
  {
    service: 'Microsoft.Storage'
  }
]

param tags object

var resourceNameSuffix  = uniqueString(resourceGroup().id)
var storageAccountName = '${storageAccountNamePrefix}${resourceNameSuffix}'
var nfs =  (fileShareType == 'NFS') ? true : false

// Resources
resource aks 'Microsoft.ContainerService/managedClusters@2021-05-01' = {
  name: clusterName
  location: location
  tags: tags
  //identity: {
  //  type: 'SystemAssigned'
  //}
  properties: {
    dnsPrefix: dnsPrefix
    agentPoolProfiles: [
      {
        count: agentCount
        vmSize: agentVMSize
        osDiskSizeGB: osDiskSizeGB
        vnetSubnetID: nfs ? subnet.id : null
        maxPods: 110
        osType: 'Linux'
        mode: 'System'
        name: 'agentpool'
      }
    ]
    servicePrincipalProfile:{
      clientId: aksClientId
      secret: aksClientSecret
    }
    linuxProfile: {
      adminUsername: linuxAdminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshRSAPublicKey
          }
        ]
      }
    }
    networkProfile: nfs ? {
      networkPlugin: 'azure'
      serviceCidr: '10.2.0.0/24'
      dnsServiceIP: '10.2.0.10'
      dockerBridgeCidr: '172.17.0.1/16'
    } : null
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = if (nfs) {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = if (nfs) {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefix
    serviceEndpoints: serviceEndpoints
  }
}

var storageAccountSkuName = (environmentType == 'prod') ? 'Premium_ZRS' : 'Premium_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'FileStorage'
  properties: {
    accessTier: 'Hot'
    networkAcls: nfs ? {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: subnet.id
        }
      ]
    } : null
    supportsHttpsTrafficOnly: nfs ? false : true
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2021-04-01' = {
  parent: storageAccount
  name: 'default'
}

resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    accessTier: 'Premium'
    shareQuota: 128
    enabledProtocols: nfs ? 'NFS' : 'SMB'
    rootSquash: nfs ? 'NoRootSquash' : null
  }
}

// Outputs
output controlPlaneFQDN string = aks.properties.fqdn
output storageAccountName string = storageAccountName
