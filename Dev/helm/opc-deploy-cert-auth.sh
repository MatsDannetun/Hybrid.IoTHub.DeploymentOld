#!/bin/bash

resourceGroupName=${1}
storageAccountName=${2}
iotHubName=${3}
deploymentName=${4}
k8sNamespace=${5}
k8sIdAppLabel=${6}
equipmentNumber=${7}
aksName=${8}
deviceId=${9}
iothubGwUrn=${10}
iothubGwContainerName=${11}

echo "resourceGroupName: $resourceGroupName, storageAccountName: $storageAccountName, iotHubName: $iotHubName, deploymentName: $deploymentName, k8sNamespace: $k8sNamespace, k8sIdAppLabel: $k8sIdAppLabel, equipmentNumber: $equipmentNumber, aksName: $aksName, deviceId: $deviceId"

# Current Helm chart uses Helm release name as app label.
k8sAppLabel=${deploymentName}

# Get storage key.
storageKey=$(az storage account keys list -n $storageAccountName --query "[?keyName=='key1'].value" -o tsv)
printf "\n%s\n" "Storage account name: ${storageAccountName}"
printf "%s\n\n" "Storage account key: ${storageKey}"

# Needed for IoT Hub device-identity subgroup installation.
az config set extension.use_dynamic_install=yes_without_prompt

# Get IoT Hub hostname.
iotHubHostname=$(az iot hub show -n $iotHubName --query "properties.hostName" -o tsv)

# iotHubDeviceIdGateway is also used for Id of identity in identity service. Naming rules of identity service apply
iotHubDeviceIdGateway="${deviceId}-gateway"
iotHubDeviceIdConfigurator="${deviceId}-configurator"
# Create new IoT Hub device.
echo "Create device $iotHubDeviceIdGateway"
az iot hub device-identity create -g ${resourceGroupName} -n ${iotHubName} -d "$iotHubDeviceIdGateway" --am x509_thumbprint --od ./
echo "Create device  $iotHubDeviceIdConfigurator"
az iot hub device-identity create -g ${resourceGroupName} -n ${iotHubName} -d "$iotHubDeviceIdConfigurator" --am shared_private_key
for i in {1..5}; do
  echo "Try to get connection string for ${iotHubDeviceIdConfigurator}. Attempt $i"
  configuratorDeviceConnectionString=$(az iot hub device-identity connection-string show -n "${iotHubName}" -d "${iotHubDeviceIdConfigurator}" -o tsv) && break ||
  sleep 5
done


# List files in local working directory.
printf "\n%s\n\n" "Local working directory:"
pwd
ls -al
          
# Inspect private and public keys.
printf "\n%s\n\n" "Private key details:"
openssl rsa -in "./${iotHubDeviceIdGateway}-key.pem" -check

printf "\n%s\n\n" "Public key details:"
openssl x509 -in "./${iotHubDeviceIdGateway}-cert.pem" -text -noout

# Use MyCO Identity Service connection string.
gatewayDeviceConnectionString="id=${iotHubDeviceIdGateway}"
printf "\n%s\n" "Identity service device connection string: ${gatewayDeviceConnectionString}"

# Get the Event Hub compatible endpoint.
ehCompatibleEp=$(az iot hub connection-string show -n ${iotHubName} --default-eventhub -o tsv)
printf "%s\n\n" "Event Hub compatible endpoint: ${ehCompatibleEp}"

# Get kube config.
az aks get-credentials -g ${resourceGroupName} -n ${aksName}
printf "\n%s\n\n" "Kube config:"
cat /home/vsts/.kube/config

# Overwrite the default values.yaml.
cat << EOF > ./override.yaml
deployment:
  disableHostNodeSelector: true
deviceId: "${deviceId}"
equiNr: "${equipmentNumber}"
deviceConnectionString: "${gatewayDeviceConnectionString}"
namespace: "${k8sNamespace}"
iothubgateway:
  urn: "${iothubGwUrn}"
cloudconfig:
  iothubconnectionstring: "${configuratorDeviceConnectionString}"
EOF

# Get IoT Hub device certificate fingerprint.
iotFingerprint=$(az iot hub device-identity show -g ${resourceGroupName} -n ${iotHubName} -d ${iotHubDeviceIdGateway} --query "authentication.x509Thumbprint.primaryThumbprint" -o tsv)

# Obtain and prune SSL fingerprint so as to agree with IoT Hub fingerprint format.
sslFingerprint=$(openssl x509 -in ./${iotHubDeviceIdGateway}-cert.pem -noout -fingerprint)
sslFingerprint=${sslFingerprint##*=}
sslFingerprint=${sslFingerprint//:/}

printf "\n%s\n" "IoT fingerprint: ${iotFingerprint}"
printf "%s\n\n" "SSL fingerprint: ${sslFingerprint}"

# Only overwrite Identity Service default yaml config for new device.
if [[ ${sslFingerprint} == ${iotFingerprint} ]]
then
    # Replace newline in key files by string literal '\n'and store in variables.
    key=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "./${iotHubDeviceIdGateway}-key.pem")
    cert=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' "./${iotHubDeviceIdGateway}-cert.pem")

    cat << EOF >> ./override.yaml
preloadIdentity:
  identity:
  - id: "${iotHubDeviceIdGateway}"
    type: "aziot"
    spec: 
      hubName: "${iotHubHostname}"
      deviceId: "${iotHubDeviceIdGateway}"
      x509Auth: 
        keyId: "${iotHubDeviceIdGateway}"
        certId: "${iotHubDeviceIdGateway}"
  certificate:
  - id: "${iotHubDeviceIdGateway}"
    pem: "${cert}"
  key:
  - id: "${iotHubDeviceIdGateway}"
    pem: "${key}"
EOF
fi

sleep 1
printf "\n\n"
echo "-----BEGIN override.yaml-----"
cat ./override.yaml
echo "-----END override.yaml-----"
echo ""

# Helm issue, use --set-string for values to be base64 encoded by Helm template.
helm upgrade --install ${deploymentName} "./Dev/pipeline/helm/${deploymentName}" \
             --set-string storageAccount.key="${storageKey}",storageAccount.name="${storageAccountName}" \
             -f ./override.yaml

# Necessary to restart IoT Hub gateway container to force download of new 
# certificate credentials in case of new device.
if [[ ${sslFingerprint} == ${iotFingerprint} ]]
then
    # Wait for pods to be ready before starting IoT Hub gateway container
    #kubectl wait -n ${k8sNamespace} --for=condition=ready pod -l app=${k8sAppLabel} --timeout=90s
    #kubectl wait -n ${k8sNamespace} --for=condition=ready pod -l app=${k8sIdAppLabel} --timeout=60s
    sleep 60

    # Get name of pod for which to restart container.
    podName=$(kubectl get pods -n ${k8sNamespace} -o jsonpath="{.items[*].metadata.name}" -l app=${k8sAppLabel})
    printf "\n%s\n\n" "Pod name:"
    echo ${podName}
          
    # Force container restart.
    kubectl exec -n ${k8sNamespace} pod/${podName} -c ${iothubGwContainerName} -- /bin/sh -c "kill 1"
    kubectl wait -n ${k8sNamespace} --for=condition=ready pod -l app=${k8sAppLabel} --timeout=60s
    printf "\n%s\n\n" "Pods in ${k8sNamespace}:"
    kubectl get pods -n ${k8sNamespace}
fi
