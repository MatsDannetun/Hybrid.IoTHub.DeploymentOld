
// Global parameters
param location string

// Local parameters exposed to top level
@allowed([
  'yes'
  'no'
])
@description('Conditional IoT deployment.  Must be yes or no.')
param dpsDeployment string

@description('Specify the name of the Iot hub.')
param iotHubNamePrefix string

@description('Specify the name of Storage')
param storageAccountNamePrefix string

@description('Specify the name of the provisioning service.')
param provisioningServiceNamePrefix string

@description('The SKU to use for the IoT Hub.')
param iotSkuName string 

@description('The number of IoT Hub units.')
param iotSkuUnits int

@description('Storage SKU for IoT Hub attached storage')
param storageSku string = 'Standard_LRS'

param tags object

var resourceNameSuffix  = uniqueString(resourceGroup().id)
var iotHubName = '${iotHubNamePrefix}-${resourceNameSuffix}'
var storageName = '${take(storageAccountNamePrefix, 11)}${resourceNameSuffix}'
var iotHubKeyName = 'iothubowner'
var provisioningServiceName = '${provisioningServiceNamePrefix}-${resourceNameSuffix}'

resource storage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'Storage'
  sku: {
      name: storageSku
  }
}

resource iotHub 'Microsoft.Devices/IotHubs@2021-07-01' = {
  name: iotHubName
  location: location
  tags: tags
  sku: {
    name: iotSkuName
    capacity: iotSkuUnits
  }
  properties: {
    storageEndpoints: {
      '$default': {
          sasTtlAsIso8601: 'PT1H'
          connectionString: 'DefaultEndpointsProtocol=https;EndpointSuffix=${environment().suffixes.storage};AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value}'
          containerName: iotHubName
      }
    }
  }
}

var dps = (dpsDeployment == 'yes') ? true : false

resource provisioningService 'Microsoft.Devices/provisioningServices@2020-03-01' = if (dps) {
  name: provisioningServiceName
  location: location
  tags: tags
  sku: {
    name: iotSkuName
    capacity: iotSkuUnits
  }
  properties: {
    iotHubs: [
      {
        connectionString: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=${iotHubKeyName};SharedAccessKey=${listkeys(resourceId('Microsoft.Devices/Iothubs/Iothubkeys', iotHubName, iotHubKeyName), '2020-03-01').primaryKey}'
        location: location
      }
    ]
  }
}

output iotHubName string = iotHubName
output storageAccountName string = storageName
