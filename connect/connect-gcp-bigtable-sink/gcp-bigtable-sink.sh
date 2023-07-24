#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi
INSTANCE=${2:-test-instance}

cd ../../connect/connect-gcp-bigtable-sink
GCP_KEYFILE="${PWD}/keyfile.json"
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
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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
playground topic produce -t stats --nb-messages 1 --forced-value '{"users": {"name":"Bob","friends": "1000"}}' --key "simple-key-1" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "users",
      "type": {
        "name": "columnfamily",
        "type": "record",
        "fields": [
          {
            "name": "name",
            "type": "string"
          },
          {
            "name": "friends",
            "type": "string"
          }
        ]
      }
    }
  ]
}
EOF
playground topic produce -t stats --nb-messages 1 --forced-value '{"users": {"name":"Jess","friends": "10000"}}' --key "simple-key-2" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF
playground topic produce -t stats --nb-messages 1 --forced-value '{"users": {"name":"John","friends": "10000"}}' --key "simple-key-3" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF

log "Creating GCP BigTable Sink connector"
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
    "table.name.format" : "kafka_\${topic}",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
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
