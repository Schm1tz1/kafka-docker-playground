connector="${args[--connector]}"
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        log "💤 No $connector_type connector is running !"
        exit 1
    fi
fi

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
    log "⏯️ Resuming $connector_type connector $connector"
    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl -s --request PUT \"https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/resume\" --header \"authorization: Basic $authorization\""
    else
        get_connect_url_and_security
        handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" \"$connect_url/connectors/$connector/resume\""
    fi

    log "⏯️ $connector_type connector $connector has been resumed successfully"

    sleep 1
    playground connector status --connector $connector
done