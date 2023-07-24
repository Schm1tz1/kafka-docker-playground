#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Splunk S2S source connector"
playground connector create-or-update --connector splunk-s2s-source << EOF
{
               "connector.class": "io.confluent.connect.splunk.s2s.SplunkS2SSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "splunk-s2s-events",
               "splunk.collector.index.default": "default-index",
               "splunk.s2s.port": "9997",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF

sleep 5

echo "log event 1" > splunk-s2s-test.log
echo "log event 2" >> splunk-s2s-test.log
echo "log event 3" >> splunk-s2s-test.log

log "Copy the splunk-s2s-test.log file to the Splunk UF Docker container"
docker cp splunk-s2s-test.log splunk-uf:/opt/splunkforwarder/splunk-s2s-test.log

log "Configure the UF to monitor the splunk-s2s-test.log file"
docker exec -i splunk-uf sudo ./bin/splunk add monitor -source /opt/splunkforwarder/splunk-s2s-test.log -auth admin:password

log "Configure the UF to connect to Splunk S2S Source connector"
docker exec -i splunk-uf sudo ./bin/splunk add forward-server connect:9997

sleep 5

log "Verifying topic splunk-s2s-events"
set +e
# rely on timeout command
timeout 20 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic splunk-s2s-events --from-beginning > /tmp/result.log  2>&1
set -e
grep "log event 1" /tmp/result.log
grep "log event 2" /tmp/result.log
grep "log event 3" /tmp/result.log

