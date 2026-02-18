// Main infrastructure template for VostokLogger telemetry system
targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Project name prefix for resource naming')
param projectName string = 'vostoklogger'

@description('MQTT Filter container image (leave as placeholder for first deployment)')
param mqttFilterImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('MQTT Broker address (e.g. mqtt.example.com:1883)')
param mqttBroker string = ''

@description('MQTT Topic to subscribe (default: #)')
param mqttTopic string = '#'

// Variables - naming convention
var uniqueSuffix = uniqueString(resourceGroup().id)
var eventHubNamespaceName = '${projectName}-eh-${uniqueSuffix}'
var eventHubName = 'telemetry'
var dataLakeStorageName = '${projectName}dl${take(uniqueSuffix, 6)}'
var acrName = '${projectName}acr${take(uniqueSuffix, 6)}'
var containerAppsEnvironmentName = '${projectName}-cae'
var mqttFilterAppName = '${projectName}-mqtt'
var loggerFuncAppName = '${projectName}-logger'

// Event Hub Namespace - BASIC tier (самый дешевый!)
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    kafkaEnabled: false
  }
}

// Event Hub - минимальная конфигурация для экономии
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1  // минимум для Basic tier
    partitionCount: 1           // минимум для экономии (Basic tier не поддерживает больше 1)
  }
}

// Data Lake Storage Account - Standard_LRS (самый дешевый)
resource dataLakeStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: dataLakeStorageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'  // Самый дешевый, локально избыточное хранилище
  }
  properties: {
    isHnsEnabled: true           // Data Lake Gen2
    accessTier: 'Hot'            // Для частого доступа
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// Blob service для storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: dataLakeStorage
  name: 'default'
}

// Azure Container Registry - Basic tier (самый дешевый ~$5/мес)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// Container для parquet файлов
resource parquetContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'telemetry'
  properties: {
    publicAccess: 'None'
  }
}

// Container Apps Environment - Consumption plan (дешево, платим только за использование)
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Container App для MQTT фильтра
resource mqttFilterApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: mqttFilterAppName
  location: location
  identity: {
    type: 'SystemAssigned'  // Managed Identity для доступа к Azure ресурсам
  }
  properties: {
    environmentId: containerAppsEnv.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: null  // Внешний доступ не нужен
      secrets: [
        {
          name: 'acr-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mqtt-filter'
          image: mqttFilterImage
          resources: {
            cpu: json('0.25')     // Минимум CPU
            memory: '0.5Gi'       // Минимум памяти
          }
          env: [
            {
              name: 'EVENTHUB_NAMESPACE'
              value: '${eventHubNamespaceName}.servicebus.windows.net'
            }
            {
              name: 'EVENTHUB_NAME'
              value: eventHubName
            }
            {
              name: 'MQTT_BROKER'
              value: mqttBroker
            }
            {
              name: 'MQTT_TOPIC'
              value: mqttTopic
            }
            {
              name: 'MQTT_USERNAME'
              secretRef: 'mqtt-username'  // Связка готова, обнови секрет
            }
            {
              name: 'MQTT_PASSWORD'
              secretRef: 'mqtt-password'  // Связка готова, обнови секрет
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0  // Масштабирование до 0 для экономии
        maxReplicas: 1
      }
    }
  }
}

// Storage Account для Azure Function (требуется отдельный)
resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: '${projectName}funcst${take(uniqueSuffix, 6)}'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// App Service Plan для Azure Function - Consumption (Y1)
resource functionAppPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${projectName}-func-plan'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

// Azure Function App - Consumption plan
resource loggerFuncApp 'Microsoft.Web/sites@2023-01-01' = {
  name: loggerFuncAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: functionAppPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(loggerFuncAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'EVENTHUB_CONNECTION'
          value: listKeys('${eventHubNamespace.id}/authorizationRules/RootManageSharedAccessKey', eventHubNamespace.apiVersion).primaryConnectionString
        }
        {
          name: 'EVENTHUB_NAME'
          value: eventHubName
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${dataLakeStorage.name};AccountKey=${dataLakeStorage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'STORAGE_CONTAINER'
          value: parquetContainer.name
        }
      ]
      netFrameworkVersion: 'v8.0'
    }
  }
}

// Outputs
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output dataLakeStorageName string = dataLakeStorage.name
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerAppsEnvironmentId string = containerAppsEnv.id
output mqttFilterAppName string = mqttFilterApp.name
output loggerFuncAppName string = loggerFuncApp.name
output functionStorageAccountName string = functionStorageAccount.name
