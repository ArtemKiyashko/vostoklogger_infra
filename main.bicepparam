using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.onemesh.ru'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '1'
param eventHubName = 'messages'
param flushMaxBufferSize = 5000
param flushIntervalSeconds = 1800
param filterWebReportIds = '*'
