targetScope = 'subscription'

// Global parameters.  Provide default values as appropriate
@description('Resource group that will host OPC Azure test resources')
param resourceGroupName string

@description('The type of environment. This must be test or prod.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentType string

@description('The Azure region into which the resources should be deployed.')
param location string = deployment().location

@allowed([
  'yes'
  'no'
])
@description('Conditional AKS deployment.  Must be yes or no.')
param aksDeployment string

@allowed([
  'yes'
  'no'
])
@description('Conditional IoT deployment.  Must be yes or no.')
param iotDeployment string

// Default parameter values for AKS infrastructure
param clusterName string = 'iactest-aks'
//param aksClientId string
//param aksClientSecret string
param dnsPrefix string = 'iactest'
param osDiskSizeGB int = 0
param agentCount int = 1
param agentVMSize string = 'standard_d4s_v3'
param linuxAdminUsername string = 'adminuser'
param sshRSAPublicKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEArVtdMyEhnT0lo3GgHiP1bJILaSCtsQIdVoau4CHFCPKuPC23mSrVbY9qiobxu9mNHqb23YPwKutAugAkJLQG0SwqJZyZb6fWq1g7K9YtxY8IiPf//3P5zclYpRV7ehnh7zuZtmpm1AXBnuAuHStathkoMpQftLyQ5HfPXD3L5K2n3YyXuBmyyATVXmXodxtPWKmL18ejymf1Nno8xXms2dP9qEve9aBRRvrZJALs4tZYbQB8aRnLn4p39N7wTIKcbTb5mUFLPhOMWpAsuzJ8UK2gv7Z9Qu4EMxsYOitMIsH6kX5ykchMy3nRKef8HohKZZah9EuzEzmh3cIPGfaDQQ== rsa-key-20210909'

// Default parameter values for storage account
param storageAccountNamePrefix string = 'iactest'
param fileShareName string = 'iactestshare'
param fileShareType string

// Default parameter values for IoT infrastructure
param iotHubNamePrefix string = 'iactest-iothub'
param iotStorageAccountNamePrefix string = 'iaciotst'
param provisioningServiceNamePrefix string = 'iactest-dps'
param iotSkuName string = 'S1'
param iotSkuUnits int = 1
param dpsDeployment string

// Fix version and correct time format later
param tags object = {
    owner: 'Team Hybrid'
    project: 'hybrid IaC'
    version:  'To be completed'
    timestamp: utcNow()
    env: environmentType
}
var additionalAksTags = {
  'service': 'virtualsfh'
}
var aksTags = union(tags, additionalAksTags)

var deployAks = (aksDeployment == 'yes') ? true : false
var deployIot = (iotDeployment == 'yes') ? true : false

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: resourceGroupName
  location: deployment().location
  tags: tags
}
