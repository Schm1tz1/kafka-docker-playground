topic="${args[--topic]}"
compatibility="${args[--compatibility]}"

environment=`get_environment_used`

if [ "$environment" == "error" ]
then
  logerror "File containing restart command /tmp/playground-command does not exist!"
  exit 1 
fi

ret=$(get_sr_url_and_security)

sr_url=$(echo "$ret" | cut -d "@" -f 1)
sr_security=$(echo "$ret" | cut -d "@" -f 2)

if [[ ! -n "$topic" ]]
then
    logwarn "--topic flag was not provided, applying command to all topics"
    check_if_continue
    topic=$(playground get-topic-list --skip-connect-internal-topics)
    if [ "$topic" == "" ]
    then
        logerror "❌ No topic found !"
        exit 1
    fi
fi

items=($topic)
for topic in ${items[@]}
do
  log "🛡️ Set compatibility for subject ${topic}-value to $compatibility"
  curl $sr_security -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data "{\"compatibility\": \"$compatibility\"}" "${sr_url}/config/${topic}-value"
done