#!/usr/bin/env pwsh
<#
.Synopsis
   This script fetches e2etest env / secrets from resource group that are required for executing E2E tests
.DESCRIPTION
   Fetches the following secrets from E2E test resource group
   - IotHubOwnerConnectionString: Connection string for managing the IoT Hub
   - IotHubEventHubConnectionString: Connection string for reading/writing to IoT Hub built-in Event Hub endpoint
   - IotStorageConnectionString: Connection string for Blob Storage connected to IoT Hub
   - AksStorageConnectionString: Connection string that allows acess to azure file share mounted in AKS
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>

param(
[Parameter(Mandatory = $true)] $ResourceGroupName,
[string] $IotHubName = $null,
[string] $IotStorageName = $null,
[string] $AksStorageName = $null
)
$ErrorActionPreference = "Stop"
Import-Module "Az.Resources"

# Prefix of storage accounts that are used to select storage, if AksStorageName or IotStorageName are null
$IotStorageAccountPrefix = "iaciotst"

function Get-AzStorageConnectionString() {
param(
[Parameter(Mandatory = $true)] $ResourceGroupName,
[Parameter(Mandatory = $true)] $AccountName
)
   $storageAccountEndpoint = "DefaultEndpointsProtocol=https;AccountName=" + $storageAccountName + ";AccountKey=" + $storageAccountKey + ";EndpointSuffix=core.windows.net"
   $key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -AccountName $AccountName)[0].Value
   return "DefaultEndpointsProtocol=https;AccountName=$AccountName;AccountKey=$key;EndpointSuffix=core.windows.net"
}

##### Try to determine variables 
# Note: Use Get-AzResource -ResourceGroupName $ResourceGroupName with the provider would be a lot cleaner here, but it seems the call just returns empty for some
#       newly created resource groups (btw. why is it Resourcegroup for Iot Hub but ResourceGroupName for Storage? Can't Azure ever be consistent?
Write-Host "Using ResourceGroupName: $ResourceGroupName"
if (! $IotHubName) {
   $IotHubName = (Get-AzIotHub | Where-Object ResourceGroup -eq $ResourceGroupName)[0].Name
}
Write-Host "Using IotHubName: $IotHubName"

if (! $AksStorageName) {
   $AksStorageName = (Get-AzStorageAccount | Where { $_.ResourceGroupName -eq $ResourceGroupName -and (-not $_.StorageAccountName.StartsWith($IotStorageAccountPrefix)) })[0].StorageAccountName
}
Write-Host "Using AksStorageName: $AksStorageName"

if (! $IotStorageName) {
   $IotStorageName = (Get-AzStorageAccount | Where { $_.ResourceGroupName -eq $ResourceGroupName -and $_.StorageAccountName.StartsWith($IotStorageAccountPrefix) })[0].StorageAccountName
}
Write-Host "Using IotStorageName: $IotStorageName"

### Storage
$iotStorageConnectionString = Get-AzStorageConnectionString -ResourceGroupName $ResourceGroupName -AccountName $IotStorageName
$aksStorageConnectionString = Get-AzStorageConnectionString -ResourceGroupName $ResourceGroupName -AccountName $AksStorageName
$aksStorageShareName = (Get-AzStorageAccount  -ResourceGroupName $ResourceGroupName -AccountName $AksStorageName | Get-AzStorageShare)[0].Name

### IoT Hub
$iotHub = Get-AzIotHub -ResourceGroupName $ResourceGroupName -Name $IotHubName
$iotHubOwnerKey = (Get-AzIotHubKey  -ResourceGroupName $ResourceGroupName  -Name $IotHubName -KeyName "iothubowner").PrimaryKey
$iotHubOwnerConnectionString = (Get-AzIotHubConnectionString -ResourceGroupName $ResourceGroupName  -Name $IotHubName -KeyName "iothubowner").PrimaryConnectionString

$iotHubEventHubConnectionString = "Endpoint=$($iotHub.Properties.EventHubEndpoints.events.Endpoint);SharedAccessKeyName=iothubowner;SharedAccessKey=$iotHubOwnerKey;EntityPath=$($iotHub.Properties.EventHubEndpoints.events.Path)"

return @{
   IotHubOwnerConnectionString = $iotHubOwnerConnectionString
   IotHubEventHubConnectionString = $iotHubEventHubConnectionString
   IotStorageConnectionString = $iotStorageConnectionString
   AksStorageConnectionString = $aksStorageConnectionString
   AksStorageShareName = $aksStorageShareName
   ResourceGroupName = $ResourceGroupName
}
