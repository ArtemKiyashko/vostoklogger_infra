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

@secure()
@description('MQTT username (secure deployment parameter)')
param mqttUsername string = ''

@secure()
@description('MQTT password (secure deployment parameter)')
param mqttPassword string = ''

@secure()
@description('Synapse SQL administrator password')
param synapseSqlPassword string = ''

@description('Object ID of the Azure AD user to be Synapse Workspace Administrator')
param synapseAdminObjectId string = ''

@description('Comma-separated allowed Meshtastic from IDs (uint)')
param filterAllowedFromIds string = ''

@description('Event Hub Namespace name (must be globally unique)')
param eventHubNamespaceName string = '${projectName}-eh-${uniqueString(resourceGroup().id)}'

@description('Event Hub name inside namespace')
param eventHubName string = 'telemetry'

// Variables - naming convention
var uniqueSuffix = uniqueString(resourceGroup().id)
var dataLakeStorageName = '${projectName}dl${take(uniqueSuffix, 6)}'
var acrName = '${projectName}acr${take(uniqueSuffix, 6)}'
var containerAppsEnvironmentName = '${projectName}-cae'
var mqttFilterAppName = '${projectName}-mqtt'
var loggerFuncAppName = '${projectName}-logger'
var logAnalyticsWorkspaceName = '${projectName}-law-${uniqueSuffix}'
var applicationInsightsName = '${projectName}-ai-${uniqueSuffix}'
var signalRName = '${projectName}-signalr-${uniqueSuffix}'
var webmapStorageName = '${projectName}web${take(uniqueSuffix, 6)}'
var webmapStaticWebsiteHost = '${webmapStorageName}.z6.web.${environment().suffixes.storage}'

// Log Analytics Workspace - required for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'  // Pay-as-you-go pricing
    }
    retentionInDays: 30  // Минимальный срок хранения для экономии
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

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
        {
          name: 'mqtt-username'
          value: mqttUsername
        }
        {
          name: 'mqtt-password'
          value: mqttPassword
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
              name: 'FILTER_ALLOWED_FROM_IDS'
              value: filterAllowedFromIds
            }
            {
              name: 'MQTT_USERNAME'
              secretRef: 'mqtt-username'  // Связка готова, обнови секрет
            }
            {
              name: 'MQTT_PASSWORD'
              secretRef: 'mqtt-password'  // Связка готова, обнови секрет
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsights.properties.ConnectionString
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
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'EVENTHUB_CONNECTION__fullyQualifiedNamespace'
          value: '${eventHubNamespaceName}.servicebus.windows.net'
        }
        {
          name: 'EVENTHUB_NAME'
          value: eventHubName
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: dataLakeStorage.name
        }
        {
          name: 'STORAGE_CONTAINER'
          value: parquetContainer.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AzureSignalRConnectionString'
          value: signalR.listKeys().primaryConnectionString
        }
        {
          name: 'POSITIONS_TABLE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
      ]
      netFrameworkVersion: 'v8.0'
      cors: {
        allowedOrigins: [
          'https://${webmapStaticWebsiteHost}'
          'http://localhost:3000'
        ]
        supportCredentials: false
      }
    }
  }
}

// Azure SignalR Service - Free tier for realtime map updates
resource signalR 'Microsoft.SignalRService/signalR@2024-03-01' = {
  name: signalRName
  location: location
  sku: {
    name: 'Free_F1'
    tier: 'Free'
    capacity: 1
  }
  kind: 'SignalR'
  properties: {
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'  // Serverless mode for Azure Functions integration
      }
      {
        flag: 'EnableConnectivityLogs'
        value: 'true'
      }
    ]
    cors: {
      allowedOrigins: [
        'https://${webmapStaticWebsiteHost}'  // Static website origin
        'http://localhost:3000'  // Local development
      ]
    }
    serverless: {
      connectionTimeoutInSeconds: 30
    }
  }
}

// Storage Account for static website (webmap)
resource webmapStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: webmapStorageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true  // Required for static website
    supportsHttpsTrafficOnly: true
  }
}

// Enable static website on webmap storage
resource webmapBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: webmapStorage
  name: 'default'
}

// $web container is created automatically when static website is enabled,
// but declaring it ensures Bicep tracks it as part of infrastructure.
resource webmapWebContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: webmapBlobService
  name: '$web'
  properties: {
    publicAccess: 'None' // Static website serves via its own endpoint, not blob public access
  }
}

// Table service on function storage for hot position data (day history)
resource functionTableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: functionStorageAccount
  name: 'default'
}

// Table for position records
resource positionsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: functionTableService
  name: 'positions'
}

// Synapse Workspace - Serverless SQL for Parquet analytics
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: '${projectName}-synapse-${uniqueSuffix}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${dataLakeStorage.name}.dfs.${environment().suffixes.storage}'
      filesystem: parquetContainer.name
    }
    sqlAdministratorLogin: 'sqladmin'
    sqlAdministratorLoginPassword: synapseSqlPassword
    cspWorkspaceAdminProperties: {
      initialWorkspaceAdminObjectId: synapseAdminObjectId
    }
  }
}

// Allow Azure services to access Synapse
resource synapseFirewallAllowAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Allow all IPs to access Synapse (personal project)
resource synapseFirewallAllowAll 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
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
output applicationInsightsName string = applicationInsights.name
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output synapseWorkspaceName string = synapseWorkspace.name
output synapseSqlEndpoint string = synapseWorkspace.properties.connectivityEndpoints.sql
output signalRName string = signalR.name
output webmapStorageName string = webmapStorage.name
output webmapStaticWebsiteUrl string = 'https://${webmapStaticWebsiteHost}'
