json=${args[json]}

if [ "$json" = "-" ]
then
    # stdin
    json_content=$(cat "$json")
else
    json_content=$json
fi

json_file=/tmp/json
echo "$json_content" > $json_file

# JSON is invalid
if ! echo "$json_content" | jq -e . > /dev/null 2>&1
then
    set +e
    jq_output=$(jq . "$json_file" 2>&1)
    error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

    if [[ -n "$error_line" ]]; then
        logerror "❌ Invalid JSON at line $error_line"
    fi
    set -e

    if [[ $(type -f bat 2>&1) =~ "not found" ]]
    then
        cat -n $json_file
    else
        bat $json_file --highlight-line $error_line
    fi

    exit 1
fi

ret=$(get_ccloud_connect)

environment=$(echo "$ret" | cut -d "@" -f 1)
cluster=$(echo "$ret" | cut -d "@" -f 2)
authorization=$(echo "$ret" | cut -d "@" -f 3)

connector="${args[--connector]}"

is_create=1
connectors=$(playground get-ccloud-connector-list)
items=($connectors)
for con in ${items[@]}
do
    if [[ "$con" == "$connector" ]]
    then
        is_create=0
    fi
done

if [ $is_create == 1 ]
then
    log "🛠️ Creating connector $connector"
else
    log "🔄 Updating connector $connector"
fi

set +e
curl_output=$(curl $security -s -X PUT \
     -H "Content-Type: application/json" \
     -H "authorization: Basic $authorization" \
     --data @$json_file \
     https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config)

ret=$?
set -e
if [ $ret -eq 0 ]
then
    error_code=$(echo "$curl_output" | jq -r .error_code)
    if [ "$error_code" != "null" ]
    then
        message=$(echo "$curl_output" | jq -r .message)
        logerror "Command failed with error code $error_code"
        logerror "$message"
    else
        if [ $is_create == 1 ]
        then
            log "✅ Connector $connector was successfully created"
            log "🥁 Waiting a few seconds to get new status"
        else
            log "✅ Connector $connector was successfully updated"
            log "🥁 Waiting a few seconds to get new status"
        fi
        sleep 8
        playground ccloud-connector status
    fi
else
    logerror "❌ curl request failed with error code $ret!"
    exit 1
fi