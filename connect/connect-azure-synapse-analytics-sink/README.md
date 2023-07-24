# Azure Synapse Analytics Sink connector



## Objective

Quickly test [Azure Synapse Analytics Sink](https://docs.confluent.io/kafka-connectors/azure-sql-dw/current/overview.html) connector.


## How to run

Simply run:

```
$ playground run -f azure-synapse-analytics-sink<tab>
```

## Details of what the script is doing

Logging to Azure using browser (or using environment variables `AZ_USER` and `AZ_PASS` if set)

```bash
az login
```

All the SQL Data Warehouse setup is automated:

```bash
AZURE_NAME=pg${USER}wh${GITHUB_RUN_NUMBER}${TAG}
AZURE_NAME=${AZURE_NAME//[-._]/}
AZURE_RESOURCE_GROUP=$AZURE_NAME
AZURE_SQL_NAME=$AZURE_NAME
AZURE_FIREWALL_RULL_NAME=$AZURE_NAME
AZURE_DATA_WAREHOUSE_NAME=$AZURE_NAME
AZURE_REGION=westeurope
AZURE_SQL_URL="jdbc:sqlserver://$AZURE_SQL_NAME.database.windows.net:1433"
PASSWORD=$(date +%s | cksum | base64 | head -c 32 ; echo)

# Creating Azure Resource Group $AZURE_RESOURCE_GROUP
az group create \
    --name $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION
# Creating SQL server instance $AZURE_SQL_NAME
az sql server create \
    --name $AZURE_SQL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --location $AZURE_REGION  \
    --admin-user myadmin \
    --admin-password $PASSWORD
# Enable a server-level firewall rule
MY_IP=$(curl https://ipinfo.io/ip)
az sql server firewall-rule create \
    --name $AZURE_FIREWALL_RULL_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP
# Create a SQL Data Warehouse instance
az sql dw create \
    --name $AZURE_DATA_WAREHOUSE_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --server $AZURE_SQL_NAME
```

The connector is created with:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.azuresqldw.AzureSqlDwSinkConnector",
                "tasks.max": "1",
                "topics": "products",
                "auto.create": "true",
                "auto.evolve": "true",
                "table.name.format": "kafka_\${topic}",
                "azure.sql.dw.url": "${file:/data:AZURE_SQL_URL}",
                "azure.sql.dw.user": "myadmin",
                "azure.sql.dw.password": "${file:/data:PASSWORD}",
                "azure.sql.dw.database.name": "${file:/data:AZURE_DATA_WAREHOUSE_NAME}",
                "confluent.license": "",
                "confluent.topic.bootstrap.servers": "broker:9092",
                "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/azure-sql-dw-sink/config | jq .
```

Messages are sent to `products` topic using:

```bash
$ playground topic produce -t products --nb-messages 2 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

playground topic produce -t products --nb-messages 1 --forced-value '{"name": "notebooks", "price": 1.99, "quantity": 5}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF
```

Check Azure Synapse Analytics for Data

```bash
$ docker run -i fabiang/sqlcmd -S "$AZURE_SQL_NAME.database.windows.net,1433" -I -U "myadmin" -P "$PASSWORD" -d "$AZURE_DATA_WAREHOUSE_NAME" -Q "select * from kafka_products;"
```

Results:

```
-------------------------------------------------------------------------------------------------------------------
         10     0.99000001 tape
          5           1.99 notebooks
          3           2.75 scissors

(3 rows affected)
```

Deleting resource group:

```bash
$ az group delete --name $AZURE_RESOURCE_GROUP --yes
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
