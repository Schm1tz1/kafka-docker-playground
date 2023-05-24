#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-connect-onprem-to-cloud.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic products-avro
set -e

log "Sending messages to topic products-avro on source OnPREM cluster"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic products-avro --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" connect \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "http://schema-registry:8081",
          "src.kafka.bootstrap.servers": "broker:9092",

          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
          "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
          "value.converter.basic.auth.credentials.source": "USER_INFO",

          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "products-avro",
          "topic.config.sync": false,
          "topic.auto.create": false
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .

# In order to remove avro converter metadata added in schema, we can set:
# "value.converter.connect.meta.data": false

log "Verify we have received the data in products-avro topic"
playground topic consume --topic products-avro --min-expected-messages 3