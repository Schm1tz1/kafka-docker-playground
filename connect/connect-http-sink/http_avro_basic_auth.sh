#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic avro-topic"
playground topic produce -t avro-topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

playground debug log-level set --package "org.apache.http" --level TRACE

log "Creating http-sink connector"
playground connector create-or-update --connector http-sink << EOF
{
     "topics": "avro-topic",
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.http.HttpSinkConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "reporter.bootstrap.servers": "broker:9092",
     "reporter.error.topic.name": "error-responses",
     "reporter.error.topic.replication.factor": 1,
     "reporter.result.topic.name": "success-responses",
     "reporter.result.topic.replication.factor": 1,
     "http.api.url": "http://http-service-basic-auth:8080/api/messages",
     "request.body.format": "json",
     "auth.type": "BASIC",
     "connection.user": "admin",
     "connection.password": "password"
}
EOF


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl admin:password@localhost:9083/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log
