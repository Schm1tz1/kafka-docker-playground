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
delete_topic products
sleep 3
create_topic products
set -e

log "Sending messages to topic products on source OnPREM cluster"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic products

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.kafka.bootstrap.servers": "broker:9092",
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
          "topic.whitelist": "products",
          "topic.config.sync": false,
          "topic.auto.create": false
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .


log "Verify we have received the data in products topic"
playground topic consume --topic products --min-expected-messages 10