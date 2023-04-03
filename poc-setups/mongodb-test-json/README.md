# MongoDB sink connector example



## Objective

Quickly test [MongoDB](https://docs.mongodb.com/kafka-connector/current/) connector.




## How to run

Simply run:

```
$ ./mongo-sink.sh
```

## Details of what the script is doing


Initialize MongoDB replica set

```bash
$ docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'
```

Note: `mongodb:27017`is important here

Create a user profile

```bash
$ docker exec -i mongodb mongosh << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
```

Create the connector:

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "key.converter.schemas.enable": "false",
                    "value.converter.schemas.enable": "false",
                    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.PartialValueStrategy",
                    "value.projection.list": "Id",
                    "value.projection.type": "whitelist",
                    "database":"test",
                    "collection":"orders",
                    "topics":"orders"
          }' \
     http://localhost:8083/connectors/mongodb-sink/config | jq .
```

Sending messages to topic `orders`

```bash
$ cat message-example.json | jq -c | docker exec -i connect kafka-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders
$ cat message-example-attachment.json | jq -c | docker exec -i connect kafka-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders
```

View the record

```bash
$ docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF
```

Result is:

```
Current Mongosh Log ID:	637f7b016c017b900556293d
Connecting to:		mongodb://127.0.0.1:27017/?directConnection=true&serverSelectionTimeoutMS=2000&appName=mongosh+1.6.0
Using MongoDB:		6.0.2
Using Mongosh:		1.6.0

For mongosh info see: https://docs.mongodb.com/mongodb-shell/

------
   The server generated these startup warnings when booting
   2022-11-24T14:08:04.774+00:00: Using the XFS filesystem is strongly recommended with the WiredTiger storage engine. See http://dochub.mongodb.org/core/prodnotes-filesystem
   2022-11-24T14:08:05.321+00:00: Access control is not enabled for the database. Read and write access to data and configuration is unrestricted
   2022-11-24T14:08:05.321+00:00: You are running this process as the root user, which is not recommended
   2022-11-24T14:08:05.321+00:00: vm.max_map_count is too low
------

------
   Enable MongoDB's free cloud-based monitoring service, which will then receive and display
   metrics about your deployment (disk utilization, CPU, operation statistics, etc).

   The monitoring data will be available on a MongoDB website with a unique URL accessible to you
   and anyone you share the URL with. MongoDB may use this information to make product
   improvements and to suggest MongoDB products and deployment options to you.

   To enable free monitoring, run the following command: db.enableFreeMonitoring()
   To permanently disable this reminder, run the following command: db.disableFreeMonitoring()
------

myuser [direct: primary] test> already on db test
myuser [direct: primary] test> [
  {
    _id: ObjectId("637f7af951e3a3024a85cd8a"),
    Datum: '2022-10-17T15:31:51.338Z',
    Description: 'Start of processing for 1234567890',
    Title: 'Mail received',
    Typ: 'technical',
    Severity: 'Information',
    Id: 'e17f07a3-2802-4922-88c8-3daf95915667',
    Attachments: {},
    Tags: {
      date: '2022-10-10T12:00:02.000Z',
      subject: 'Start of processing for 1234567890',
      'mail-id': 'B3F21120-595B-44A6-D235-E4CF4E735D7D',
      from: 'mail@from.me',
      to: 'input@mail.net',
      's3-filename': '456g3vl8k5d6m30est3dl61a1bll86glndrufm88'
    },
    Source: 'input.mail.inbox',
    Name: 'MailReceived'
  },
  {
    _id: ObjectId("637f7af951e3a3024a85cd8b"),
    Datum: '2022-10-17T15:31:52.338Z',
    Description: 'Start of processing for 1234567891',
    Title: 'Mail received',
    Typ: 'technical',
    Severity: 'Information',
    Id: 'e17f07a3-2802-4922-88c8-3daf95915668',
    Attachments: {
      'message.json': 'ewogICJJZCI6ICJlMTdmMDdhMy0yODAyLTQ5MjItODhjOC0zZGFmOTU5MTU2NjciLAogICJOYW1lIjogIk1haWxSZWNlaXZlZCIsCiAgIkRhdHVtIjogIjIwMjItMTAtMTdUMTU6MzE6NTEuMzM4WiIsCiAgIlR5cCI6ICJ0ZWNobmljYWwiLAogICJTZXZlcml0eSI6ICJJbmZvcm1hdGlvbiIsCiAgIlRpdGxlIjogIk1haWwgcmVjZWl2ZWQiLAogICJEZXNjcmlwdGlvbiI6ICJTdGFydCBvZiBwcm9jZXNzaW5nIGZvciAxMjM0NTY3ODkwIiwKICAiVGFncyI6IHsKICAgICJmcm9tIjogIm1haWxAZnJvbS5tZSIsCiAgICAidG8iOiAiaW5wdXRAbWFpbC5uZXQiLAogICAgImRhdGUiOiAiMjAyMi0xMC0xMFQxMjowMDowMi4wMDBaIiwKICAgICJzdWJqZWN0IjogIlN0YXJ0IG9mIHByb2Nlc3NpbmcgZm9yIDEyMzQ1Njc4OTAiLAogICAgInMzLWZpbGVuYW1lIjogIjQ1Nmczdmw4azVkNm0zMGVzdDNkbDYxYTFibGw4NmdsbmRydWZtODgiLAogICAgIm1haWwtaWQiOiAiQjNGMjExMjAtNTk1Qi00NEE2LUQyMzUtRTRDRjRFNzM1RDdEIgogIH0sCiAgIlNvdXJjZSI6ICJpbnB1dC5tYWlsLmluYm94IiwKICAiQXR0YWNobWVudHMiOiB7CiAgfQp9Cg=='
    },
    Tags: {
      date: '2022-10-10T12:00:03.000Z',
      subject: 'Start of processing for 1234567891',
      'mail-id': 'B3F21120-595B-44A6-D235-E4CF4E735D7D',
      from: 'mail@from.me',
      to: 'input@mail.net',
      's3-filename': '456g3vl8k5d6m30est3dl61a1bll86glndrufm88'
    },
    Source: 'input.mail.inbox',
    Name: 'MailReceived'
  }
]
myuser [direct: primary] test>     Description: 'Start of processing for 1234567890',
      subject: 'Start of processing for 1234567890'
```

N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
