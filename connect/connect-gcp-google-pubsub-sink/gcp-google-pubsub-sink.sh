#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -f ${DIR}/pubsub-group-kafka-connector-1.0.0.jar ]
then
     wget https://repo1.maven.org/maven2/com/google/cloud/pubsub-group-kafka-connector/1.0.0/pubsub-group-kafka-connector-1.0.0.jar
fi

cd ../../connect/connect-gcp-google-pubsub-sink
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


# cleanup if required
set +e
log "Delete topic and subscription, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete topic-1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete subscription-1
set -e

log "Create a Pub/Sub topic called topic-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics create topic-1

log "Create a Pub/Sub subscription called subscription-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions create --topic topic-1 subscription-1


log "send data to pubsub-topic topic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic pubsub-topic --property parse.key=true --property key.separator=, << EOF
key1,{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
key2,{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
key3,{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF


sleep 10

log "Creating Google Cloud Pub/Sub Group Kafka Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.google.pubsub.kafka.sink.CloudPubSubSinkConnector",
               "tasks.max" : "1",
               "topics" : "pubsub-topic",
               "cps.project" : "'"$GCP_PROJECT"'",
               "cps.topic" : "topic-1",
               "gcp.credentials.file.path" : "/tmp/keyfile.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "metadata.publish": "true",
               "headers.publish": "true"
          }' \
     http://localhost:8083/connectors/pubsub-sink/config | jq .

sleep 120

log "Get messages from topic-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions pull subscription-1 > /tmp/result.log  2>&1
cat /tmp/result.log
grep "scissors" /tmp/result.log

# ┌──────────────────────────────────────────────────────────┬──────────────────┬──────────────┬───────────────────────────────┬──────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
# │                           DATA                           │    MESSAGE_ID    │ ORDERING_KEY │           ATTRIBUTES          │ DELIVERY_ATTEMPT │                                                                                              ACK_ID                                                                                             │
# ├──────────────────────────────────────────────────────────┼──────────────────┼──────────────┼───────────────────────────────┼──────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
# │ {"u_name": "scissors", "u_price": 2.75, "u_quantity": 3} │ 7291919715450279 │              │ kafka.offset=3                │                  │ RVNEUAYWLF1GSFE3GQhoUQ5PXiM_NSAoRRYLUxNRXHUDWxBvXDN1B1ENGXN1ZnVjXhYFBExadF9RGx9ZXESD0IqdL1BdZndjWxoAC0JSe1teGw9vVXSlkoejsvG0XW9WYuXW2dVlXrOw_bFZZiE9XBJLLD5-PTxFQV5AEkw2CURJUytDCypYEU4EISE-MD4 │
# │                                                          │                  │              │ kafka.partition=0             │                  │                                                                                                                                                                                                 │
# │                                                          │                  │              │ kafka.timestamp=1679487746962 │                  │                                                                                                                                                                                                 │
# │                                                          │                  │              │ kafka.topic=pubsub-topic      │                  │                                                                                                                                                                                                 │
# │                                                          │                  │              │ key=key1                      │                  │                                                                                                                                                                                                 │
# └──────────────────────────────────────────────────────────┴──────────────────┴──────────────┴───────────────────────────────┴──────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

log "Delete topic and subscription"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete topic-1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete subscription-1

docker rm -f gcloud-config