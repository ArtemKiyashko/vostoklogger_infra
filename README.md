# vostoklogger_infra

Bicep-шаблоны инфраструктуры Azure для системы логирования телеметрии.

## Ресурсы

- Event Hub (Basic) — прием сообщений от MQTT-фильтра
- Data Lake Storage (Standard_LRS) — хранение Parquet файлов
- Azure Container Registry (Basic) — Docker образы для MQTT filter
- Container Apps (Consumption) — хостинг MQTT filter
- Azure Function (Consumption Y1) — обработка Event Hub и запись в Parquet

**Стоимость:** ~$16-20/месяц

## Деплой

```bash
az login
az group create --name vostoklogger-rg --location westeurope
az deployment group create \
  --resource-group vostoklogger-rg \
  --template-file main.bicep \
  --parameters main.bicepparam
```

Или через Azure Pipeline (автоматически при изменении Bicep файлов).

## Добавление MQTT секретов (через Portal или CLI)

Секреты `mqtt-username` и `mqtt-password` созданы пустыми. Обнови их значения:

**Вариант 1 - Azure Portal:**
1. Container Apps → vostoklogger-mqtt → **Secrets**
2. Найди `mqtt-username` и `mqtt-password` → Edit
3. Введи реальные значения → Save

**Вариант 2 - Azure CLI:**
```bash
az containerapp secret set \
  --name vostoklogger-mqtt \
  --resource-group vostoklogger-rg \
  --secrets mqtt-username=youruser mqtt-password=yourpass
```

Environment variables уже настроены и ссылаются на эти секреты.

## Параметры

Настраиваются в [main.bicepparam](main.bicepparam):
- `location` — регион Azure
- `projectName` — префикс ресурсов
- `mqttBroker` — адрес MQTT брокера (обязательно указать)
- `mqttTopic` — топик для подписки (по умолчанию: `#`)

