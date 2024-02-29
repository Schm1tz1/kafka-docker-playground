connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
  get_ccloud_connect
  get_kafka_docker_playground_dir
  DELTA_CONFIGS_ENV=$KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/env.delta

  if [ -f $DELTA_CONFIGS_ENV ]
  then
      source $DELTA_CONFIGS_ENV
  else
      logerror "ERROR: $DELTA_CONFIGS_ENV has not been generated"
      exit 1
  fi
  if [ ! -f $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta ]
  then
      logerror "ERROR: $KAFKA_DOCKER_PLAYGROUND_DIR/.ccloud/ak-tools-ccloud.delta has not been generated"
      exit 1
  fi
else
  get_security_broker "--command-config"
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    maybe_id=""
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request GET \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/status\" --header \"authorization: Basic $authorization\""
        connectorId=$(get_ccloud_connector_lcc $connector)
        maybe_id=" ($connectorId)"
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl -s $security \"$connect_url/connectors/$connector/status\""
    fi

    type=$(echo "$curl_output" | jq -r '.type')
    log "⛏️ Altering offsets for $connector_type connector $connector"

    if [ "$type" == "source" ]
    then
        ##
        # SOURCE CONNECTOR
        ##
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
        then
            logwarn "command is not available with $connector_type $type connector"
            continue
        fi

        tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
        if [ $? != 0 ] || [ "$tag" == "" ]
        then
            logerror "❌ could not find current CP version from docker ps"
            continue
        fi

        if ! version_gt $tag "7.5.99"; then
            logerror "❌ command is available since CP 7.6 only"
            continue
        fi

        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X GET \"$connect_url/connectors/$connector/offsets\""

        file=$tmp_dir/offsets-$connector.json
        echo "$curl_output" | jq . > $file

        editor=$(playground config get editor)
        if [ "$editor" != "" ]
        then
            log "✨ Update the connector offsets as per your needs, save and close the file to continue"
            if [ "$editor" = "code" ]
            then
                code --wait $file
            else
                $editor $file
            fi
        else
            if [[ $(type code 2>&1) =~ "not found" ]]
            then
                logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
                exit 1
            else
                log "✨ Update the connector offsets as per your needs, save and close the file to continue"
                code --wait $file
            fi
        fi

        playground connector stop --connector $connector

        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X PATCH -H \"Content-Type: application/json\" --data @$file \"$connect_url/connectors/$connector/offsets\""

        echo "$curl_output" | jq .

        playground connector resume --connector $connector

        playground connector source-offsets get --connector $connector
    else
        ##
        # SINK CONNECTOR
        ##
        # if [[ -n "$verbose" ]]
        # then
        #     log "🐞 CLI command used"
        #     echo "kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security"
        # fi
        get_environment_used
        if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ] || [[ "$environment" == "ccloud" ]]
        then
            logwarn "command is not available with $connector_type $type connector"
            continue
        else
            file=$tmp_dir/offsets-$connector.csv

            # FIXTHIS, replace with delete/create
            tag=$(docker ps --format '{{.Image}}' | egrep 'confluentinc/cp-.*-connect-base:' | awk -F':' '{print $2}')
            if [ $? != 0 ] || [ "$tag" == "" ]
            then
                logerror "❌ could not find current CP version from docker ps"
                continue
            fi

            if ! version_gt $tag "7.4.99"; then
                logerror "❌ command is available since CP 7.5 only"
                continue
            fi

            playground connector stop --connector $connector

            echo "topic,partition,current-offset" > $file
            docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector $security --export --reset-offsets --to-current --all-topics --dry-run >> $file

            editor=$(playground config get editor)
            if [ "$editor" != "" ]
            then
                log "✨ Update the connector offsets as per your needs, save and close the file to continue"
                if [ "$editor" = "code" ]
                then
                    code --wait $file
                else
                    $editor $file
                fi
            else
                if [[ $(type code 2>&1) =~ "not found" ]]
                then
                    logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
                    exit 1
                else
                    log "✨ Update the connector offsets as per your needs, save and close the file to continue"
                    code --wait $file
                fi
            fi

            # remove any empty lines and header
            grep -v '^$' "$file" > $tmp_dir/tmp && mv $tmp_dir/tmp "$file"
            grep -v 'current-offset' "$file" > $tmp_dir/tmp && mv $tmp_dir/tmp "$file"

            docker cp $file $container:/tmp/offsets.csv > /dev/null 2>&1
            docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector $security --reset-offsets --from-file /tmp/offsets.csv --execute

            playground connector resume --connector $connector
        fi
    fi
done