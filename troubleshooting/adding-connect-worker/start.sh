#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating SFTP Sink connector with 4 tasks"
playground connector create-or-update --connector sftp-sink << EOF
{
        "topics": "test_sftp_sink",
               "tasks.max": "4",
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
               "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq

log "Adding a second connect worker"
docker-compose -f ../../environment/plaintext/docker-compose.yml -f "${PWD}/docker-compose.plaintext.yml" -f "${PWD}/docker-compose.add-connect-worker.yml" up -d

../../scripts/wait-for-connect-and-controlcenter.sh connect2 $@

sleep 5

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/sftp-sink/status \
  --header 'accept: application/json' | jq