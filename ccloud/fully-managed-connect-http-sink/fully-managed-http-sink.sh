#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

log "Creating http-topic topic in Confluent Cloud"
set +e
create_topic http-topic
set -e

log "Sending messages to topic http-topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker run -i --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG}  kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic http-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

cat << EOF > connector.json
{
     "connector.class": "HttpSink",
     "name": "HttpSink",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "http-topic",
     "input.data.format": "AVRO",
     "http.api.url": "http://httpstat.us/200/",
     "behavior.on.error": "fail",
     "tasks.max" : "1"
}
EOF

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

connectorName=$(cat connector.json| jq -r .name)
connectorId=$(get_ccloud_connector_lcc $connectorName)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10

log "Do you want to delete the fully managed connector ?"
check_if_continue

log "Deleting fully managed connector"
delete_ccloud_connector connector.json
