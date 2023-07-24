#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# if version_gt $TAG_BASE "5.9.0"; then
#      log "Hbase does not support JDK 11, see https://hbase.apache.org/book.html#java"
#      # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/907
#      exit 107
# fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi
INSTANCE=${2:-test-instance}

GCP_KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi

set +e
playground topic delete --topic _confluent-command
set -e

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic stats
set -e

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.gcp-bigtable.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF
set -e
log "Create a BigTable Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances create $INSTANCE --project $GCP_PROJECT --cluster $INSTANCE --cluster-zone=us-east1-c --display-name="playground-bigtable-instance" --instance-type=DEVELOPMENT

log "Sending messages to topic stats"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic stats --property parse.key=true --property key.separator=, --property key.schema='{"type" : "string", "name" : "id"}' --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name": "name", "type": "string"},{"name": "friends", "type": "string"}]}}]}' << EOF
"simple-key-1", {"users": {"name":"Bob","friends": "1000"}}
"simple-key-2", {"users": {"name":"Jess","friends": "10000"}}
"simple-key-3", {"users": {"name":"John","friends": "10000"}}
EOF


log "Creating GCP BigTbale Sink connector"
playground connector create-or-update --connector gcp-bigtable-sink << EOF
{
     "connector.class": "io.confluent.connect.gcp.bigtable.BigtableSinkConnector",
     "tasks.max" : "1",
     "topics" : "stats",
     "auto.create" : "true",
     "gcp.bigtable.credentials.path": "/tmp/keyfile.json",
     "gcp.bigtable.instance.id": "$INSTANCE",
     "gcp.bigtable.project.id": "$GCP_PROJECT",
     "auto.create.tables": "true",
     "auto.create.column.families": "true",
     "table.name.format" : "kafka_\${topic}"
}
EOF

sleep 30

log "Verify data is in GCP BigTable"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $INSTANCE read kafka_stats > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Bob" /tmp/result.log

log "Delete table"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $INSTANCE deletetable kafka_stats

log "Deleting instance"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF

docker rm -f gcloud-config
