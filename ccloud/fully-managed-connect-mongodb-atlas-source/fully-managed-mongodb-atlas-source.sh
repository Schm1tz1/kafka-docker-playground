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


log "Creating MongoDB source connector"
playground ccloud-connector create-or-update --connector mongodb-source2 << EOF
{
     "connector.class" : "MongoDbAtlasSource",
     "name": "mongodb-source2",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "tasks.max" : "1",
     "topic.prefix":"mongo",
     "connection.host": "<>",
     "connection.user": "<>",
     "connection.password": "<>",
     "database": "sample_mflix",
     "_collection": "movies",

     "pipeline": "[{\"\$match\": {\"ns.coll\": {\"\$regex\": /^(movies|sessions)$/}}}]",

     "poll.await.time.ms": "1000",
     "poll.max.batch.size": "1000",
     "startup.mode": "copy_existing",
     "output.data.format": "JSON",
     "change.stream.full.document": "updateLookup"
}
EOF

sleep 5

playground topic consume

exit 0
