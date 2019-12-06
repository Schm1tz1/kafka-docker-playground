#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/sasl-plain/start.sh "${PWD}/docker-compose.sasl-plain.yml"

# INFO Principal = User:sftp is Denied Operation = Describe from host = 192.168.224.6 on resource = Topic:LITERAL:test_sftp_sink (kafka.authorizer.logger)
# INFO Principal = User:sftp is Denied Operation = Describe from host = 192.168.224.6 on resource = Group:LITERAL:connect-sftp-sink (kafka.authorizer.logger)
docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal User:sftp --consumer --topic test_sftp_sink --group connect-sftp-sink


# Current ACLs for resource `Group:LITERAL:connect-sftp-sink`:
#         User:sftp has Allow permission for operations: Read from hosts: *

# Current ACLs for resource `Topic:LITERAL:test_sftp_sink`:
#         User:sftp has Allow permission for operations: Read from hosts: *
#         User:sftp has Allow permission for operations: Describe from hosts: *


# [2019-12-06 11:17:45,758] INFO Principal = User:sftp is Denied Operation = Create from host = 172.18.0.6 on resource = Cluster:LITERAL:kafka-cluster (kafka.authorizer.logger)
# [2019-12-06 11:17:45,759] INFO Principal = User:sftp is Denied Operation = Create from host = 172.18.0.6 on resource = Topic:LITERAL:test_sftp_sink (kafka.authorizer.logger)
docker exec broker kafka-acls --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal User:sftp --operation CREATE --topic test_sftp_sink

echo "Creating SFTP Sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "sftp-sink",
        "config": {
               "topics": "test_sftp_sink",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
               "flush.size": "3",
               "schema.compatibility": "NONE",
               "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
               "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
               "sftp.host": "sftp-server",
               "sftp.port": "22",
               "sftp.username": "foo",
               "sftp.password": "pass",
               "sftp.working.dir": "/upload",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "consumer.override.sasl.mechanism": "PLAIN",
               "consumer.override.security.protocol": "SASL_PLAINTEXT",
               "consumer.override.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"sftp\" password=\"sftp-secret\";",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic test_sftp_sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test_sftp_sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --producer.config /tmp/client.properties

sleep 10

echo "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
ls ./upload/topics/test_sftp_sink/partition\=0/

# brew install avro-tools
avro-tools tojson ./upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro