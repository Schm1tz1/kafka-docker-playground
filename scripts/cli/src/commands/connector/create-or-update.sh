connector="${args[--connector]}"
json=${args[json]}
level=${args[--level]}
package=${args[--package]}
validate=${args[--validate]}
verbose="${args[--verbose]}"

connector_type=$(playground state get run.connector_type)

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    if [[ -n "$level" ]]
    then
        logerror "❌ --level is set but not supported with $connector_type connector"
        exit 1
    fi

    if [[ -n "$package" ]]
    then
        logerror "❌ --package is set but not supported with $connector_type connector"
        exit 1
    fi
fi

environment=$(playground state get run.environment_before_switch)
if [ "$environment" = "" ]
then
    environment=$(playground state get run.environment)
fi

if [ "$environment" = "" ]
then
    environment="plaintext"
fi

if [ "$json" = "-" ]
then
    # stdin
    json_content=$(cat "$json")
else
    json_content=$json
fi

tmp_dir=$(mktemp -d -t pg-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
json_file=$tmp_dir/connector.json
new_json_file=$tmp_dir/connector_new.json
json_validate_file=$tmp_dir/json_validate_file

echo "$json_content" > $json_file

# JSON is invalid
if ! echo "$json_content" | jq -e .  > /dev/null 2>&1
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

is_create=1
connectors=$(playground get-connector-list)
items=($connectors)
for con in ${items[@]}
do
    if [[ "$con" == "$connector" ]]
    then
        is_create=0
    fi
done

if [[ -n "$validate" ]]
then
    log "✅ --validate is set"
    set +e
    connector_class=$(echo "$json_content" | jq -r '."connector.class"')

    if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
    then
        get_ccloud_connect
        handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connector-plugins/$connector_class/config/validate"
    else
        get_connect_url_and_security
        add_connector_config_based_on_environment "$environment" "$json_content"
        # add mandatory name field
        new_json_content=$(echo $json_content | jq ". + {\"name\": \"$connector\"}")

        echo "$new_json_content" > $new_json_file
        handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$new_json_file $connect_url/connector-plugins/$connector_class/config/validate"
    fi
    set -e
    if ! echo "$curl_output" | jq -e .  > /dev/null 2>&1
    then
        set +e
        echo "$curl_output" > $json_validate_file
        jq_output=$(jq . "$json_validate_file" 2>&1)
        error_line=$(echo "$jq_output" | grep -oE 'parse error.*at line [0-9]+' | grep -oE '[0-9]+')

        if [[ -n "$error_line" ]]; then
            logerror "❌ Invalid JSON at line $error_line"
        fi
        set -e

        if [[ $(type -f bat 2>&1) =~ "not found" ]]
        then
            cat -n $json_validate_file
        else
            bat $json_validate_file --highlight-line $error_line
        fi

        exit 1
    fi

    is_valid=1
    for row in $(echo "$curl_output" | jq -r '.configs[] | @base64'); do
        _jq() {
            echo ${row} | base64 --decode | jq -r ${1}
        }

        name=$(_jq '.value.name')
        value=$(_jq '.value.value')
        errors=$(_jq '.value.errors')

        if [ "$(echo "$errors" | jq 'length')" -gt 0 ]
        then
            is_valid=0
            logerror "❌ validation error for config <$name=$value>" 
            echo "$errors" | jq .
        fi
    done

    if [ $is_valid -eq 1 ]
    then
        log "✅ $connector_type connector config is valid !" 
    else
        exit 1
    fi
fi

if [ $is_create == 1 ]
then
    log "🛠️ Creating $connector_type connector $connector"
else
    log "🔄 Updating $connector_type connector $connector"
fi

if [ "$connector_type" == "$CONNECTOR_TYPE_FULLY_MANAGED" ] || [ "$connector_type" == "$CONNECTOR_TYPE_CUSTOM" ]
then
    get_ccloud_connect
    handle_ccloud_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" -H \"authorization: Basic $authorization\" --data @$json_file https://api.confluent.cloud/connect/v1/environments/$environment/clusters/$cluster/connectors/$connector/config"
else
    get_connect_url_and_security
    add_connector_config_based_on_environment "$environment" "$json_content"
    echo "$json_content" > $new_json_file
    handle_onprem_connect_rest_api "curl $security -s -X PUT -H \"Content-Type: application/json\" --data @$new_json_file $connect_url/connectors/$connector/config"
fi

if [[ -n "$level" ]]
then
    if [[ -n "$package" ]]
    then
        playground debug log-level set --level $level --package $package
    else
        playground connector log-level --connector $connector --level $level
    fi
fi
if [ $is_create == 1 ]
then
    log "✅ $connector_type connector $connector was successfully created"
else
    log "✅ $connector_type connector $connector was successfully updated"
fi
if [ -z "$GITHUB_RUN_NUMBER" ]
then
    echo "$json_content" > "/tmp/config-$connector"
    playground connector show-config --connector "$connector"
fi
playground connector show-config-parameters --connector "$connector" --only-show-json
log "🥁 Waiting a few seconds to get new status"
sleep 5
set +e
playground connector status --connector $connector
if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
then
    playground connector open-docs --only-show-url
fi
set -e