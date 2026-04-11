using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.onemesh.ru'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '3511387040,1821533326'
param meshtasticPsk = 'AQ=='
param eventHubName = 'messages'
param flushMaxBufferSize = 1
param flushIntervalSeconds = 10
param filterWebReportIds = '3511387040,1821533326'
param mapBufferMinutes = 120
