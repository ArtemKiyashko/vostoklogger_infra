using './main.bicep'

param location = 'westeurope'
param projectName = 'vostoklogger'
param mqttBroker = 'mqtt.onemesh.ru'
param mqttTopic = 'msh/RU/#'
param filterAllowedFromIds = '1770339052,1311579232,143261324,80063200,3148676576,1770326680,2661165020,3919925383'
param eventHubName = 'messages'
