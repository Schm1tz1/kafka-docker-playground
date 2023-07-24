#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_docker_and_memory
verify_installed "docker-compose"
check_docker_compose_version
check_bash_version

# https://docs.docker.com/compose/profiles/
profile_control_center_command=""
if [ -z "$ENABLE_CONTROL_CENTER" ]
then
  log "🛑 control-center is disabled"
else
  log "💠 control-center is enabled"
  log "Use http://localhost:9021 to login"
  profile_control_center_command="--profile control-center"
fi

profile_ksqldb_command=""
if [ -z "$ENABLE_KSQLDB" ]
then
  log "🛑 ksqldb is disabled"
else
  log "🚀 ksqldb is enabled"
  log "🔧 You can use ksqlDB with CLI using:"
  log "docker exec -i ksqldb-cli ksql http://ksqldb-server:8088"
  profile_ksqldb_command="--profile ksqldb"
fi

# defined grafana variable and when profile is included/excluded
profile_grafana_command=""
if [ -z "$ENABLE_JMX_GRAFANA" ]
then
  log "🛑 Grafana is disabled"
else
  log "📊 Grafana is enabled"
  profile_grafana_command="--profile grafana"
fi
profile_kcat_command=""
if [ -z "$ENABLE_KCAT" ]
then
  log "🛑 kcat is disabled"
else
  log "🧰 kcat is enabled"
  profile_kcat_command="--profile kcat"
fi
if [ -z "$ENABLE_CONDUKTOR" ]
then
  log "🛑 conduktor is disabled"
else
  log "🐺 conduktor is enabled"
  log "Use http://localhost:8080/console (admin/admin) to login"
  profile_conduktor_command="--profile conduktor"
fi

#define kafka_nodes variable and when profile is included/excluded
profile_kafka_nodes_command=""
if [ -z "$ENABLE_KAFKA_NODES" ]
then
  profile_kafka_nodes_command=""
else
  log "3️⃣  Multi broker nodes enabled"
  profile_kafka_nodes_command="--profile kafka_nodes"
fi

OLDDIR=$PWD
cd ${OLDDIR}/../../environment/sasl-ssl/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/"
cd ${OLDDIR}/../../environment/sasl-ssl

ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE=""
DOCKER_COMPOSE_FILE_OVERRIDE=$1
if [ -f "${DOCKER_COMPOSE_FILE_OVERRIDE}" ]
then
  ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE="-f ${DOCKER_COMPOSE_FILE_OVERRIDE}"
  check_arm64_support "${DIR}" "${DOCKER_COMPOSE_FILE_OVERRIDE}"
fi

docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} build
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} down -v --remove-orphans
docker-compose -f ../../environment/plaintext/docker-compose.yml -f ../../environment/sasl-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} up -d
log "📝 To see the actual properties file, use cli command playground get-properties -c <container>"
command="source ${DIR}/../../scripts/utils.sh && docker-compose -f ${DIR}/../../environment/plaintext/docker-compose.yml -f ${DIR}/../../environment/sasl-ssl/docker-compose.yml ${ENABLE_DOCKER_COMPOSE_FILE_OVERRIDE} ${profile_control_center_command} ${profile_ksqldb_command} ${profile_grafana_command} ${profile_kcat_command} ${profile_conduktor_command} ${profile_kafka_nodes_command} up -d"
echo "$command" > /tmp/playground-command
log "✨ If you modify a docker-compose file and want to re-create the container(s), run cli command playground container recreate"



cd ${OLDDIR}

if [ "$#" -ne 0 ]
then
    shift
fi
../../scripts/wait-for-connect-and-controlcenter.sh $@

display_jmx_info