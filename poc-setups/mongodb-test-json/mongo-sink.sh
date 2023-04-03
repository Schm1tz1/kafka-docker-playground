#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongosh --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Sending messages to topic orders"
cat message-example.json | jq -c | docker exec -i connect kafka-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders
cat message-example-attachment.json | jq -c | docker exec -i connect kafka-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders

log "Creating MongoDB sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "key.converter.schemas.enable": "false",
                    "value.converter.schemas.enable": "false",
                    "transforms": "IdRenamer",
                    "transforms.IdRenamer.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
                    "transforms.IdRenamer.renames": "Id:_id",
                    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.ProvidedInValueStrategy",
                    "value.projection.list": "Id",
                    "value.projection.type": "whitelist",
                    "database":"test",
                    "collection":"orders",
                    "topics":"orders"
          }' \
     http://localhost:8083/connectors/mongodb-sink/config | jq .

sleep 10

log "View record"
docker exec -i mongodb mongosh << EOF
use test
db.orders.find().pretty();
EOF

docker exec -i mongodb mongosh << EOF > output.txt
use test
db.orders.find().pretty();
EOF
grep "1234567890" output.txt
rm output.txt