#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" -a

log "Sleep 90 seconds"
sleep 90

docker container logs --tail=300 filebeat

log "Verify we have received the data in syslog topic"
playground topic consume --topic topic-log --min-expected-messages 100 --timeout 60