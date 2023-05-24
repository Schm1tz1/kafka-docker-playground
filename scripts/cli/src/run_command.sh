DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
open="${args[--open]}"
tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"
connector_jar="${args[--connector-jar]}"
enable_ksqldb="${args[--enable-ksqldb]}"
enable_c3="${args[--enable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sr_maven_plugin_app="${args[--enable-sr-maven-plugin-app]}"
enable_sql_datagen="${args[--enable-sql-datagen]}"

if [ "$test_file" = "" ]
then
  logerror "ERROR: test_file is not provided as argument!"
  exit 1
fi

if [[ $test_file == *"@"* ]]
then
  test_file=$(echo "$test_file" | cut -d "@" -f 2)
fi
  
if [ ! -f "$test_file" ]
then
  logerror "ERROR: test_file $test_file does not exist!"
  exit 1
fi

if [[ "$test_file" != *".sh" ]]
then
  logerror "ERROR: test_file $test_file is not a .sh file!"
  exit 1
fi

test_file_directory="$(dirname "${test_file}")"
filename=$(basename -- "$test_file")
extension="${filename##*.}"

base1="${test_file_directory##*/}" # connect-cdc-oracle12-source
dir1="${test_file_directory%/*}" #connect
dir2="${dir1##*/}/$base1" # connect/connect-cdc-oracle12-source
final_dir=$(echo $dir2 | tr '/' '-') # connect-connect-cdc-oracle12-source

flag_list=""
if [[ -n "$tag" ]]
then
  flag_list="--tag=$tag"
  export TAG=$tag
fi

if [[ -n "$connector_tag" ]]
then
  flag_list="$flag_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG=$connector_tag
fi

if [[ -n "$connector_zip" ]]
then
  if [[ $connector_zip == *"@"* ]]
  then
    connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-zip=$connector_zip"
  export CONNECTOR_ZIP=$connector_zip
fi

if [[ -n "$connector_jar" ]]
then
  if [[ $connector_jar == *"@"* ]]
  then
    connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
  fi
  flag_list="$flag_list --connector-jar=$connector_jar"
  export CONNECTOR_JAR=$connector_jar
fi

if [[ -n "$enable_ksqldb" ]]
then
  flag_list="$flag_list --enable-ksqldb"
  export ENABLE_KSQLDB=true
fi

if [[ -n "$enable_c3" ]]
then
  flag_list="$flag_list --enable-control-center"
  export ENABLE_CONTROL_CENTER=true
fi

if [[ -n "$enable_conduktor" ]]
then
  flag_list="$flag_list --enable-conduktor"
  export ENABLE_CONDUKTOR=true
fi

if [[ -n "$enable_multiple_brokers" ]]
then
  flag_list="$flag_list --enable-multiple-broker"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  flag_list="$flag_list --enable-multiple-connect-workers"
  export ENABLE_CONNECT_NODES=true
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  flag_list="$flag_list --enable-jmx-grafana"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sr_maven_plugin_app" ]]
then
  flag_list="$flag_list --enable-sr-maven-plugin-app"
  export ENABLE_SR_MAVEN_PLUGIN_NODE=true
fi

if [[ -n "$enable_sql_datagen" ]]
then
  flag_list="$flag_list --enable-sql-datagen"
  export SQL_DATAGEN=true
fi

if [[ -n "$open" ]]
then
  if config_has_key "editor"
  then
    editor=$(config_get "editor")
    log "📖 Opening ${test_file} using configured editor $editor"
    $editor ${test_file}
    check_if_continue
  else
    if [[ $(type code 2>&1) =~ "not found" ]]
    then
      logerror "Could not determine an editor to use as default code is not found - you can change editor by updating config.ini"
      exit 1
    else
      log "📖 Opening ${test_file} with code (default) - you can change editor by updating config.ini"
      code ${test_file}
      check_if_continue
    fi
  fi
fi

if [ "$flag_list" != "" ]
then
  log "🚀 Running example with flags"
  log "⛳ Flags used are $flag_list"
else
  log "🚀 Running example without any flags"
fi
set +e
playground container kill-all
set -e
echo "playground run -f $test_file $flag_list ${other_args[*]}" > /tmp/playground-run
log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
trap 'rm /tmp/playground-run-command-used;echo "";sleep 3;set +e;playground connector status;playground connector versions' EXIT
touch /tmp/playground-run-command-used
bash $filename ${other_args[*]}
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
if [ $ret -eq 0 ]
then
    log "####################################################"
    log "✅ RESULT: SUCCESS for $filename ($ELAPSED - $CUMULATED)"
    log "####################################################"
else
    logerror "####################################################"
    logerror "🔥 RESULT: FAILURE for $filename ($ELAPSED - $CUMULATED)"
    logerror "####################################################"

    display_docker_container_error_log
fi