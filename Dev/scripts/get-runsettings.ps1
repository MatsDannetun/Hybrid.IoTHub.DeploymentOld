#!/usr/bin/env pwsh
<#
.Synopsis
   Get contents for runsettings that are used to execute NUnit E2E test project
.DESCRIPTION
   Uses previously fetched E2ETestEnv to generate runsettings for E2E test project.
   The script does NOT handle connection to AKS cluster! Because that is handled using K8s context.

.PARAMETER K8sNamespace
   The K8sNamespace that will be used during execution (this basically is the "SFH" id)

.PARAMETER K8sDeploymentName
   Name of the Deployment our containers are part of

.PARAMETER ConfiguratorDeviceId
   Name of device to be used by cloud configurator
   
.PARAMETER TemplatePath
   Path to template for creation of runsettings. If not specified MyCO.IIoT.E2E/MyCO.IIoT.E2E.Tests/template-runsettings.xml will be used
#>

param(
[Parameter(Mandatory = $true)] $E2ETestEnv,
$ConfiguratorDeviceId = "sfh1-configurator",
$K8sNamespace = "sfh1",
$K8sDeploymentName = "opclive-data",
$TemplatePath = $null
)
$ErrorActionPreference = "Stop"

if (! $TemplatePath) {
   $TemplatePath = "$PSScriptRoot/../../MyCO.IIoT.E2E/MyCO.IIoT.E2E.Tests/template-runsettings.xml"
}

$fileContent = Get-Content $TemplatePath -Raw

$fileContent = $fileContent `
               -replace "{{iot-hub-event-hub-connection-string}}", $E2ETestEnv.IotHubEventHubConnectionString `
               -replace "{{iot-hub-service-connection-string}}", $E2ETestEnv.IotHubOwnerConnectionString `
               -replace "{{iot-storage-account-connection-string}}", $E2ETestEnv.IotStorageConnectionString `
               -replace "{{aks-storage-account-connection-string}}", $E2ETestEnv.AksStorageConnectionString `
			   -replace "{{configurator-deviceid}}", $ConfiguratorDeviceId `
               -replace "{{share-name}}", $E2ETestEnv.AksStorageShareName `
               -replace "{{namespace}}", $K8sNamespace `
               -replace "{{deployment-name}}", $K8sDeploymentName `
               -replace "{{resource-group-name}}", $E2ETestEnv.ResourceGroupName

return $fileContent