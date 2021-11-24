Param(
    [string]
    $ResourceGroupName,
    [string]
    $DeploymentName,
    [string]
    $Namespace,
    [string]
    $EquipmentNumber,
    [string]
    $AksName,
    [string]
    $DeviceId,
    [string]
    $IotHubName,
    [string]
    $StorageAccountName,
    [string]
    $ShareName
)

echo $resourceGroupName
echo $storageAccountName
echo $iotHubName
echo $deploymentName
echo $namespace
echo $equipmentNumber
echo $aksName
echo $deviceId 
echo $shareName

 # Get storage key.
 $storageKeyArgs = @{
    ResourceGroupName = $resourceGroupName 
    AccountName = $storageAccountName
  }
  $storageKey = (Get-AzStorageAccountKey  @storageKeyArgs)[0].Value

  # Set storage context.
  $storageContextArgs = @{
    StorageAccountName = $storageAccountName
    StorageAccountKey = $storageKey
  }
  $storageContext = New-AzStorageContext @storageContextArgs
  Set-AzCurrentStorageAccount -Context $storageContext

  # Add equiment number to pn.json.
  $publisherConfigurationPath = ".\e2e-tests\pipeline\data\publisherNodeConfiguration.json"
  (Get-Content -path $publisherConfigurationPath -Raw) `
               -replace '<sfh-equipmentNumber>',$equipmentNumber `
               | Set-Content -Path $publisherConfigurationPath

  # Upload pn.json to Azure.  Turn off all warnings, confirmation, 
  # prompts, etc., in case of overwriting an existing file.
  $storageFileContentArgs = @{
    ShareName = $shareName
    Source = $publisherConfigurationPath
    Path = "pn.json"
    ErrorAction = "SilentlyContinue"
    WarningAction = "SilentlyContinue"
    Force = $true
    Confirm = $false
  }
  # Set-AzStorageFileContent @storageFileContentArgs

  # Create IoT device.
  $iotHubDeviceArgs = @{
    ResourceGroupName = $resourceGroupName
    IotHubName = $iotHubName
    DeviceId = $deviceId
  }
  $existingDevice = Get-AzIotHubDevice @iotHubDeviceArgs

  if ($existingDevice.id -eq $deviceId) {
      echo "Device with id ${deviceId} already exists.  Skipping step ..."
  } else {
      echo "No device with id ${deviceId}.  Creating device ..."
      Add-AzIotHubDevice @iotHubDeviceArgs -AuthMethod "shared_private_key"
  }

  # Get connection string.
  $deviceConnectionString = (Get-AzIotHubDCS @iotHubDeviceArgs).ConnectionString

  # Get kube config.
  Import-AzAksCredential -ResourceGroupName $resourceGroupName -Name $aksName -Force

  # Install OPC live data in AKS cluster
  helm upgrade --install $deploymentName ".\Dev\helm\${deploymentName}" `
               --set-string storageAccount.key="$storageKey",storageAccount.name="$storageAccountName",deviceId="$deviceId",equiNr="$equipmentNumber",deviceConnectionString="$deviceConnectionString",namespace="$namespace"
