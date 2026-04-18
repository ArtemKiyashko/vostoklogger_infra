using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.onemesh.ru'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '1'
param meshtasticPsk = 'AQ=='
param eventHubName = 'messages'
param flushMaxBufferSize = 5000
param flushIntervalSeconds = 1800
param filterWebReportIds = '3511387040,1821533326'
param mapBufferMinutes = 120
