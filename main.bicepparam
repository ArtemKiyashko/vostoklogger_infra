using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.meshtastic.org'
param mqttTopic = 'msh/RU/#'
param eventHubName = 'telemetry'
