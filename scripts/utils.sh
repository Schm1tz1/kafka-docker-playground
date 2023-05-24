DIR_UTILS="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR_UTILS}/../scripts/cli/src/lib/utils_function.sh

# Setting up TAG environment variable
#
if [ -z "$TAG" ]
then
    # TAG is not set, use default:
    export TAG=7.4.0
    # to handle ubi8 images
    export TAG_BASE=$TAG
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
      then
        log "💫 Using default CP version $TAG"
        log "🎓 Use --tag option to specify different version, see https://kafka-docker-playground.io/#/how-to-use?id=🎯-for-confluent-platform-cp"
      fi
    fi
    export CP_KAFKA_IMAGE=confluentinc/cp-server
    export CP_BASE_IMAGE=confluentinc/cp-base-new
    export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
    export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-cli:latest
    export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    export CONNECT_USER="appuser"
    export CP_CONNECT_IMAGE=confluentinc/cp-server-connect-base
    set_kafka_client_tag
else
    if [ -z "$CP_KAFKA_IMAGE" ]
    then
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
      then
        log "🚀 Using specified CP version $TAG"
      fi
    fi
    # to handle ubi8 images
    export TAG_BASE=$(echo $TAG | cut -d "-" -f1)
    first_version=${TAG_BASE}
    second_version=5.2.99
    if version_gt $first_version $second_version; then
        if [ "$first_version" = "5.3.6" ]
        then
          logwarn "Workaround for 5.3.6 image broker, using custom image vdesabou/cp-server !"
          export CP_KAFKA_IMAGE=vdesabou/cp-server
        else
          export CP_KAFKA_IMAGE=confluentinc/cp-server
        fi
    else
        export CP_KAFKA_IMAGE=confluentinc/cp-enterprise-kafka
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export CP_BASE_IMAGE=confluentinc/cp-base-new
    else
        export CP_BASE_IMAGE=confluentinc/cp-base
    fi
    second_version=5.4.99
    if version_gt $first_version $second_version; then
        export CP_KSQL_IMAGE=confluentinc/cp-ksqldb-server
        export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksqldb-cli:${TAG_BASE}
    else
        export CP_KSQL_IMAGE=confluentinc/cp-ksql-server
        export CP_KSQL_CLI_IMAGE=confluentinc/cp-ksql-cli:${TAG_BASE}
    fi
    second_version=5.2.99
    if version_gt $first_version $second_version; then
        if [ "$first_version" == "5.3.6" ]
        then
          logwarn "Workaround for ST-6539, using custom image vdesabou/cp-server-connect-base !"
          export CP_CONNECT_IMAGE=vdesabou/cp-server-connect-base
        else
          export CP_CONNECT_IMAGE=confluentinc/cp-server-connect-base
        fi
    else
        export CP_CONNECT_IMAGE=confluentinc/cp-kafka-connect-base
    fi
    second_version=5.3.99
    if version_gt $first_version $second_version; then
        export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL=""
    else
        if [ -z "$LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL" ]
        then
          log "👴 Legacy config for client connecting to HTTPS SR is set, see https://docs.confluent.io/platform/current/schema-registry/security/index.html#additional-configurations-for-https"
          export LEGACY_CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_SSL="-Djavax.net.ssl.trustStore=/etc/kafka/secrets/kafka.connect.truststore.jks -Djavax.net.ssl.trustStorePassword=confluent -Djavax.net.ssl.keyStore=/etc/kafka/secrets/kafka.connect.keystore.jks -Djavax.net.ssl.keyStorePassword=confluent"
        fi
    fi
    set_kafka_client_tag
fi

# Setting grafana agent based  
if [ -z "$ENABLE_JMX_GRAFANA" ]
then
  # defaulting to empty variable since this is default in kafka-run-class.sh & avoid warning
  export GRAFANA_AGENT_ZK=""
  export GRAFANA_AGENT_BROKER=""
  export GRAFANA_AGENT_CONNECT=""
  export GRAFANA_AGENT_PRODUCER=""
  export GRAFANA_AGENT_CONSUMER=""
else
  export GRAFANA_AGENT_ZK="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/zookeeper.yml"
  export GRAFANA_AGENT_BROKER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/broker.yml"
  export GRAFANA_AGENT_CONNECT="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/connect.yml"
  export GRAFANA_AGENT_PRODUCER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/kafka-producer.yml"
  export GRAFANA_AGENT_CONSUMER="-javaagent:/usr/share/jmx_exporter/pyroscope-0.11.2.jar -javaagent:/usr/share/jmx_exporter/jmx_prometheus_javaagent-0.16.1.jar=1234:/usr/share/jmx_exporter/kafka-consumer.yml"
fi

# Migrate SimpleAclAuthorizer to AclAuthorizer #1276
if version_gt $TAG "5.3.99"
then
  export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.authorizer.AclAuthorizer"
else
  export KAFKA_AUTHORIZER_CLASS_NAME="kafka.security.auth.SimpleAclAuthorizer"
fi


if [ ! -z "$CONNECTOR_TAG" ] && [ ! -z "$CONNECTOR_ZIP" ]
then
  logerror "CONNECTOR_TAG and CONNECTOR_ZIP are both set, they cannot be used at same time!"
  exit 1
fi

###
#  CONNECTOR_TAG is set
###
if [ ! -z "$CONNECTOR_TAG" ]
then
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"environment"* ]]
  then
    # log "DEBUG: start.sh from environment folder. Skipping..."
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
    then
      log "🎯 CONNECTOR_TAG (--connector-tag option) is set with version $CONNECTOR_TAG"
    fi
    # determining the connector from current path
    docker_compose_file=""
    if [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        i=0
        my_array_connector_tag=($(echo $CONNECTOR_TAG | tr "," "\n"))
        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          CONNECTOR_VERSION="${my_array_connector_tag[$i]}"
          if [ "$CONNECTOR_VERSION" = "" ]
          then
            logwarn "CONNECTOR_TAG (--connector-tag option) was not set for element $i, setting it to latest"
            CONNECTOR_VERSION="latest"
          fi
          export CONNECT_TAG="$TAG"

          maybe_create_image

          if [ "$first_loop" = true ]
          then
              if [[ "$OSTYPE" == "darwin"* ]]
              then
                  rm -rf ${DIR_UTILS}/../confluent-hub
              else
                  sudo rm -rf ${DIR_UTILS}/../confluent-hub
              fi
          fi
          log "🎱 Installing connector $owner/$name:$CONNECTOR_VERSION"
          docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "confluent-hub install --no-prompt $owner/$name:$CONNECTOR_VERSION && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"

          if [ "$first_loop" = true ]
          then
            first_loop=false
            ###
            #  CONNECTOR_JAR is set (and also CONNECTOR_TAG)
            ###
            if [ ! -z "$CONNECTOR_JAR" ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "☕ jar file specified by CONNECTOR_JAR (--connector-jar option) $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ]
              then
                log "🎯☕ CONNECTOR_JAR (--connector-jar option) is set with $CONNECTOR_JAR"
              fi
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$name-$CONNECTOR_TAG.jar"
              set +e
              ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "$connector_path/lib/$name-$CONNECTOR_TAG.jar does not exist, the jar name to replace could not be found automatically"
                array=($(ls ${DIR_UTILS}/../confluent-hub/$connector_path/lib | grep $CONNECTOR_TAG))
                choosejar "${array[@]}"
                current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$jar"
              fi
              set -e
              log "🔮 Remplacing $name-$CONNECTOR_TAG.jar by $connector_jar_name"
              cp $CONNECTOR_JAR $current_jar_path
              maybe_create_image
            fi
          fi
          ((i=i+1))
        done
      fi
    else
      if [ -z "$IGNORE_CHECK_FOR_DOCKER_COMPOSE" ] && [ "$0" != "/tmp/playground-command" ] && [ "$0" != "/tmp/playground-command-debugging" ]
      then
        logerror "📁 Could not determine docker-compose override file from $PWD/$0 !"
        logerror "👉 Please check you're running a connector example !"
        logerror "🎓 Check the related documentation https://kafka-docker-playground.io/#/how-it-works?id=🐳-docker-override"
        exit 1
      else
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      fi
    fi
  fi
else
  ###
  #  CONNECTOR_TAG is not set
  ###
  if [[ $0 == *"wait-for-connect-and-controlcenter.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"environment"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    :
  elif [[ $0 == *"stop.sh"* ]]
  then
    if [ -z "$CONNECT_TAG" ]
    then
      export CONNECT_TAG="$TAG"
    fi
    CONNECTOR_TAG=$version
    :
  elif [[ $0 == *"run-tests"* ]]
  then
    :
  else
    docker_compose_file=""
    if [ -f "$PWD/$0" ]
    then
      docker_compose_file=$(grep "environment" "$PWD/$0" | grep DIR | grep start.sh | cut -d "/" -f 7 | cut -d '"' -f 1 | head -n1)
    fi
    if [ "${docker_compose_file}" != "" ] && [ -f "${docker_compose_file}" ]
    then
      connector_paths=$(grep "CONNECT_PLUGIN_PATH" "${docker_compose_file}" | grep -v "KSQL_CONNECT_PLUGIN_PATH" | cut -d ":" -f 2  | tr -s " " | head -1)
      if [ "$connector_paths" == "" ]
      then
        # not a connector test
        if [ -z "$CONNECT_TAG" ]
        then
          export CONNECT_TAG="$TAG"
        fi
      else
        ###
        #  Loop on all connectors in CONNECT_PLUGIN_PATH and install latest version from Confluent Hub (except for JDBC and replicator)
        ###
        first_loop=true
        rm -rf ${DIR_UTILS}/../confluent-hub

        for connector_path in ${connector_paths//,/ }
        do
          connector_path=$(echo "$connector_path" | cut -d "/" -f 5)
          owner=$(echo "$connector_path" | cut -d "-" -f 1)
          name=$(echo "$connector_path" | cut -d "-" -f 2-)

          if [ "$name" == "" ]
          then
            # can happen for filestream
            if [ -z "$CONNECT_TAG" ]
            then
              export CONNECT_TAG="$TAG"
            fi
          else
            if [ -z "$CONNECT_TAG" ]
            then
              export CONNECT_TAG="$TAG"
            fi

            ###
            #  CONNECTOR_ZIP is set
            ###
            if [ ! -z "$CONNECTOR_ZIP" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_ZIP" ]
              then
                logerror "CONNECTOR_ZIP $CONNECTOR_ZIP does not exist!"
                exit 1
              fi
              log "🎯🤐 CONNECTOR_ZIP (--connector-zip option) is set with $CONNECTOR_ZIP"
              connector_zip_name=$(basename ${CONNECTOR_ZIP})
              cp $CONNECTOR_ZIP /tmp/

              maybe_create_image

              log "🎱 Installing connector from zip $connector_zip_name"
              docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components  -v /tmp:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "confluent-hub install --no-prompt /tmp/${connector_zip_name} && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"
              first_loop=false
              continue
            fi

            version_to_get_from_hub="latest"
            if [ "$name" = "kafka-connect-replicator" ]
            then
              if [ -z "$REPLICATOR_TAG" ]
              then
                version_to_get_from_hub="$TAG"
              else
                version_to_get_from_hub="$REPLICATOR_TAG"
                log "🌍 REPLICATOR_TAG is set with $REPLICATOR_TAG"
              fi
            fi
            if [ "$name" = "kafka-connect-jdbc" ]
            then
              if ! version_gt $TAG_BASE "5.9.0"; then
                # for version less than 6.0.0, use JDBC with same version
                # see https://github.com/vdesabou/kafka-docker-playground/issues/221
                version_to_get_from_hub="$TAG_BASE"
              fi

              if [ "$TAG_BASE" = "5.0.2" ] || [ "$TAG_BASE" = "5.0.3" ]
              then
                version_to_get_from_hub="5.0.1"
              fi
            fi

            maybe_create_image

            log "🎱 Installing connector $owner/$name:$version_to_get_from_hub"
            docker run -u0 -i --rm -v ${DIR_UTILS}/../confluent-hub:/usr/share/confluent-hub-components ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "confluent-hub install --no-prompt $owner/$name:$version_to_get_from_hub && chown -R $(id -u $USER):$(id -g $USER) /usr/share/confluent-hub-components"

            version=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.version')
            release_date=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.release_date')
            documentation_url=$(cat ${DIR_UTILS}/../confluent-hub/${connector_path}/manifest.json | jq -r '.documentation_url')

            ###
            #  CONNECTOR_JAR is set
            ###
            if [ ! -z "$CONNECTOR_JAR" ] && [ "$first_loop" = true ]
            then
              if [ ! -f "$CONNECTOR_JAR" ]
              then
                logerror "☕ CONNECTOR_JAR $CONNECTOR_JAR does not exist!"
                exit 1
              fi
              log "🎯☕ CONNECTOR_JAR (--connector-jar option) is set with $CONNECTOR_JAR"
              connector_jar_name=$(basename ${CONNECTOR_JAR})
              current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$name-$version.jar"
              set +e
              ls $current_jar_path
              if [ $? -ne 0 ]
              then
                logwarn "☕ $connector_path/lib/$name-$version.jar does not exist, the jar name to replace could not be found automatically"
                array=($(ls ${DIR_UTILS}/../confluent-hub/$connector_path/lib | grep $version))
                choosejar "${array[@]}"
                current_jar_path="${DIR_UTILS}/../confluent-hub/$connector_path/lib/$jar"
              fi
              set -e
              log "🔮 Remplacing $name-$version.jar by $connector_jar_name"
              cp $CONNECTOR_JAR $current_jar_path

              maybe_create_image
            ###
            #  Neither CONNECTOR_ZIP or CONNECTOR_JAR are set
            ###
            else
              if [ -z "$CONNECT_TAG" ]
              then
                export CONNECT_TAG="$TAG"
              fi
              if [ "$first_loop" = true ]
              then
                log "💫 Using 🔗connector: $owner/$name:$version 📅release date: $release_date 🌐documentation: $documentation_url"
                # echo "💫 🔗 $owner/$name:$version 📅 $release_date 🌐 $documentation_url" > /tmp/connector_info
                log "🎓 To specify different version, check the documentation https://kafka-docker-playground.io/#/how-to-use?id=🔗-for-connectors"
                CONNECTOR_TAG=$version  
              fi
            fi
            first_loop=false
          fi
        done
      fi
    fi
  fi
  if [ -z "$CONNECT_TAG" ]
  then
    export CONNECT_TAG="$TAG"
  fi
fi
