using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.meshtastic.org'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '1311579232,143261324,80063200,3148676576,1770326680,2661165020,3919925383'
param eventHubName = 'telemetry'
param synapseAdminObjectId = 'c9a65d52-474f-47da-bd2c-b28a9663ae6e'
