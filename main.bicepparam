using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.meshtastic.org'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '4294967295'
param eventHubName = 'telemetry'
