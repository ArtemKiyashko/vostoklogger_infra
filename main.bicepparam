using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.meshtastic.org'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '3124558768,977880561,181006348,181006924,2658659236,2142230090,2687552158,1770341468,3148369212,3551612616,1337319010,2771749100,2661118724'
param eventHubName = 'telemetry'
