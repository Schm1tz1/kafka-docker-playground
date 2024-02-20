DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

root_folder=${DIR_CLI}/../..

test_file="${args[--file]}"
open="${args[--open]}"
environment="${args[--environment]}"
tag="${args[--tag]}"
connector_tag="${args[--connector-tag]}"
connector_zip="${args[--connector-zip]}"
connector_jar="${args[--connector-jar]}"

enable_ksqldb="${args[--enable-ksqldb]}"
enable_rest_proxy="${args[--enable-rest-proxy]}"
enable_c3="${args[--enable-control-center]}"
enable_conduktor="${args[--enable-conduktor]}"
enable_multiple_brokers="${args[--enable-multiple-brokers]}"
enable_multiple_connect_workers="${args[--enable-multiple-connect-workers]}"
enable_jmx_grafana="${args[--enable-jmx-grafana]}"
enable_kcat="${args[--enable-kcat]}"
enable_sql_datagen="${args[--enable-sql-datagen]}"

cluster_type="${args[--cluster-type]}"
cluster_cloud="${args[--cluster-cloud]}"
cluster_region="${args[--cluster-region]}"
cluster_environment="${args[--cluster-environment]}"
cluster_name="${args[--cluster-name]}"
cluster_creds="${args[--cluster-creds]}"
cluster_schema_registry_creds="${args[--cluster-schema-registry-creds]}"
interactive_mode=0

if [[ ! -n "$test_file" ]]
then
  interactive_mode=1
  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
      fzf_option_wrap="--preview-window=40%,wrap"
      fzf_option_pointer="--pointer=👉"
      fzf_option_rounded="--border=rounded"
  else
      fzf_option_pointer=""
      fzf_option_rounded=""
  fi

  readonly MENU_CONNECTOR="🔗 Connectors"
  readonly MENU_CCLOUD="🌤️ Confluent Cloud"
  readonly MENU_FULLY_MANAGED_CONNECTOR="🤖 Fully-Managed Connectors"
  readonly MENU_REPRO="👷‍♂️ Reproduction Models"
  readonly MENU_KSQL="🎏 ksqlDB"
  readonly MENU_SR="📝 Schema Registry"
  readonly MENU_RP="🧲 REST Proxy"
  readonly MENU_OTHER="👾 Other Playgrounds"
  readonly MENU_ALL="🌕 All"

  options=("$MENU_CONNECTOR" "$MENU_CCLOUD" "$MENU_FULLY_MANAGED_CONNECTOR" "$MENU_REPRO" "$MENU_KSQL" "$MENU_SR" "$MENU_RP" "$MENU_OTHER" "$MENU_ALL")
  res=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🚀" --header="Select a category (ctrl-c or esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)

  case "${res}" in
    "$MENU_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --connector-only)
    ;;
    "$MENU_CCLOUD")
      test_file=$(playground get-examples-list-with-fzf --ccloud-only)
    ;;
    "$MENU_FULLY_MANAGED_CONNECTOR")
      test_file=$(playground get-examples-list-with-fzf --fully-managed-connector-only)
    ;;
    "$MENU_REPRO")
      test_file=$(playground get-examples-list-with-fzf --repro-only)
    ;;
    "$MENU_KSQL")
      test_file=$(playground get-examples-list-with-fzf --ksql-only)
    ;;
    "$MENU_SR")
      test_file=$(playground get-examples-list-with-fzf --schema-registry-only)
    ;;
    "$MENU_RP")
      test_file=$(playground get-examples-list-with-fzf --rest-proxy-only)
    ;;
    "$MENU_OTHER")
      test_file=$(playground get-examples-list-with-fzf --other-playgrounds-only)
    ;;
    "$MENU_ALL")
      test_file=$(playground get-examples-list-with-fzf)
    ;;
    *)
      logerror "❌ wrong choice: $res"
      exit 1
    ;;
  esac
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

if [[ $test_file == *"ccloud"* ]]
then
  verify_installed "confluent"
  check_confluent_version 3.0.0 || exit 1
fi

test_file_directory="$(dirname "${test_file}")"
filename=$(basename -- "$test_file")

flag_list=""
if [[ -n "$tag" ]]
then
  if [[ $tag == *"@"* ]]
  then
    tag=$(echo "$tag" | cut -d "@" -f 2)
  fi
  flag_list="--tag=$tag"
  export TAG=$tag
fi

if [[ -n "$environment" ]]
then
  get_connector_paths
  if [ "$connector_paths" == "" ] && [ "$environment" != "plaintext" ]
  then
    logerror "❌ using --environment is only supported with connector examples"
    exit 1
  fi

  if [ "$environment" != "plaintext" ]
  then
    flag_list="$flag_list --environment=$environment"
    export PLAYGROUND_ENVIRONMENT=$environment
  fi
fi

if [[ -n "$connector_tag" ]]
then
  if [ "$connector_tag" == " " ]
  then
    get_connector_paths
    if [ "$connector_paths" == "" ]
    then
        logwarn "❌ skipping as it is not an example with connector, but --connector-tag is set"
        exit 1
    else
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            logwarn "skipping as plugin $owner/$name does not appear to be coming from confluent hub"
            continue
          fi

          ret=$(choose_connector_tag "$owner/$name")
          connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
          
          if [ -z "$connector_tags" ]; then
            connector_tags="$connector_tag"
          else
            connector_tags="$connector_tags,$connector_tag"
          fi
        done

        connector_tag="$connector_tags"
    fi
  fi

  flag_list="$flag_list --connector-tag=$connector_tag"
  export CONNECTOR_TAG="$connector_tag"
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
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-ksqldb is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-ksqldb"
  export ENABLE_KSQLDB=true
fi

if [[ -n "$enable_rest_proxy" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-rest-proxy is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-rest-proxy"
  export ENABLE_RESTPROXY=true
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
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-broker is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-multiple-broker"
  export ENABLE_KAFKA_NODES=true
fi

if [[ -n "$enable_multiple_connect_workers" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-multiple-connect-workers is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-multiple-connect-workers"
  export ENABLE_CONNECT_NODES=true

  # determining the docker-compose file from from test_file
  docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
  docker_compose_file="${test_file_directory}/${docker_compose_file}"
  cp $docker_compose_file /tmp/playground-backup-docker-compose.yml
  yq -i '.services.connect2 = .services.connect' /tmp/playground-backup-docker-compose.yml
  yq -i '.services.connect3 = .services.connect' /tmp/playground-backup-docker-compose.yml
  cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
fi

if [[ -n "$enable_jmx_grafana" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-jmx-grafana"
    exit 1
  fi
  flag_list="$flag_list --enable-jmx-grafana"
  export ENABLE_JMX_GRAFANA=true
fi

if [[ -n "$enable_kcat" ]]
then
  flag_list="$flag_list --enable-kcat"
  export ENABLE_KCAT=true
fi

if [[ -n "$enable_sql_datagen" ]]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    logwarn "❌ --enable-sql-datagen is not supported with ccloud examples"
    exit 1
  fi
  flag_list="$flag_list --enable-sql-datagen"
  export SQL_DATAGEN=true
fi

if [[ -n "$cluster_region" ]]
then
  if [[ $cluster_region == *"@"* ]]
  then
    cluster_region=$(echo "$cluster_region" | cut -d "@" -f 2)
  fi
  cluster_region=$(echo "$cluster_region" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
fi

if [[ -n "$cluster_type" ]] || [[ -n "$cluster_cloud" ]] || [[ -n "$cluster_region" ]] || [[ -n "$cluster_environment" ]] || [[ -n "$cluster_name" ]] || [[ -n "$cluster_creds" ]] || [[ -n "$cluster_schema_registry_creds" ]]
then
  if [ ! -z "$CLUSTER_TYPE" ]
  then
    log "🙈 ignoring environment variable CLUSTER_TYPE as one of the flags is set"
    unset CLUSTER_TYPE
  fi
  if [ ! -z "$CLUSTER_CLOUD" ]
  then
    log "🙈 ignoring environment variable CLUSTER_CLOUD as one of the flags is set"
    unset CLUSTER_CLOUD
  fi
  if [ ! -z "$CLUSTER_REGION" ]
  then
    log "🙈 ignoring environment variable CLUSTER_REGION as one of the flags is set"
    unset CLUSTER_REGION
  fi
  if [ ! -z "$ENVIRONMENT" ]
  then
    log "🙈 ignoring environment variable ENVIRONMENT as one of the flags is set"
    unset ENVIRONMENT
  fi
  if [ ! -z "$CLUSTER_NAME" ]
  then
    log "🙈 ignoring environment variable CLUSTER_NAME as one of the flags is set"
    unset CLUSTER_NAME
  fi
  if [ ! -z "$CLUSTER_CREDS" ]
  then
    log "🙈 ignoring environment variable CLUSTER_CREDS as one of the flags is set"
    unset CLUSTER_CREDS
  fi 
  if [ ! -z "$SCHEMA_REGISTRY_CREDS" ]
  then
    log "🙈 ignoring environment variable SCHEMA_REGISTRY_CREDS as one of the flags is set"
    unset SCHEMA_REGISTRY_CREDS
  fi 
fi

if [[ -n "$cluster_type" ]]
then
  flag_list="$flag_list --cluster-type $cluster_type"
  export CLUSTER_TYPE=$cluster_type
else
  if [ -z "$CLUSTER_TYPE" ]
  then
    export CLUSTER_TYPE="basic"
  fi
fi

if [[ -n "$cluster_cloud" ]]
then
  flag_list="$flag_list --cluster-cloud $cluster_cloud"
  export CLUSTER_CLOUD=$cluster_cloud
else
  if [ -z "$CLUSTER_CLOUD" ]
  then
    export CLUSTER_CLOUD="aws"
  fi
fi

if [[ -n "$cluster_region" ]]
then
  flag_list="$flag_list --cluster-region $cluster_region"
  export CLUSTER_REGION=$cluster_region
else
  if [ -z "$CLUSTER_REGION" ]
  then
    case "${CLUSTER_CLOUD}" in
      aws)
        export CLUSTER_REGION="eu-west-2"
      ;;
      azure)
        export CLUSTER_REGION="westeurope"
      ;;
      gcp)
        export CLUSTER_REGION="europe-west2"
      ;;
    esac
  fi
fi

if [[ -n "$cluster_environment" ]]
then
  if [[ $cluster_environment == *"@"* ]]
  then
    cluster_environment=$(echo "$cluster_environment" | cut -d "@" -f 2)
  fi
  if [[ $cluster_environment == *"/"* ]]
  then
    cluster_environment=$(echo "$cluster_environment" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
  fi
  flag_list="$flag_list --cluster-environment $cluster_environment"
  export ENVIRONMENT=$cluster_environment
fi

if [[ -n "$cluster_name" ]]
then
  if [[ $cluster_name == *"@"* ]]
  then
    cluster_name=$(echo "$cluster_name" | cut -d "@" -f 2)
  fi
  if [[ $cluster_name == *"/"* ]]
  then
    cluster_name=$(echo "$cluster_name" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
  fi
  flag_list="$flag_list --cluster-name $cluster_name"
  export CLUSTER_NAME=$cluster_name
fi

if [[ -n "$cluster_creds" ]]
then
  flag_list="$flag_list --cluster-creds $cluster_creds"
  export CLUSTER_CREDS=$cluster_creds
fi

if [[ -n "$cluster_schema_registry_creds" ]]
then
  flag_list="$flag_list --cluster-schema-registry-creds $cluster_schema_registry_creds"
  export SCHEMA_REGISTRY_CREDS=$cluster_schema_registry_creds
fi

if [[ -n "$open" ]]
then
  editor=$(playground config get editor)
  if [ "$editor" != "" ]
  then
    log "📖 Opening ${test_file} using configured editor $editor"
    $editor ${test_file}
    check_if_continue
  else
      if [[ $(type code 2>&1) =~ "not found" ]]
      then
          logerror "Could not determine an editor to use as default code is not found - you can change editor by using playground config editor <editor>"
          exit 1
      else
          log "📖 Opening ${test_file} with code (default) - you can change editor by using playground config editor <editor>"
          code ${test_file}
          check_if_continue
      fi
  fi
fi

if [ "$flag_list" == "" ]
then
  if [ $interactive_mode == 1 ]
  then
    declare -a flag_list=()

    readonly MENU_LETS_GO="🚀🚀🚀 I'm ready, let's go !!!" #0

    readonly MENU_ENABLE_KSQLDB="🎏 Enable ksqlDB (flag --enable-ksqldb)" #1
    readonly MENU_ENABLE_C3="💠 Enable Control Center (flag --enable-control-center)"
    readonly MENU_ENABLE_CONDUKTOR="🐺 Enable Conduktor Platform (flag --enable-conduktor)"
    readonly MENU_ENABLE_RP="🧲 Enable Rest Proxy (flag --enable-rest-proxy)" #4
    readonly MENU_ENABLE_GRAFANA="📊 Enable Grafana, Prometheus and Pyroscope (flag --enable-jmx-grafana)"
    readonly MENU_ENABLE_BROKERS="3️⃣  Enabling multiple brokers (flag --enable-multiple-broker)"
    readonly MENU_ENABLE_CONNECT_WORKERS="🥉 Enabling multiple connect workers (flag --enable-multiple-connect-workers)"
    readonly MENU_ENABLE_KCAT="🐈 Enabling kcat (flag --enable-kcat)"
    readonly MENU_ENABLE_SQL_DATAGEN="🌪️  Enable SQL Datagen injection (flag --enable-sql-datagen)" #9

    readonly MENU_DISABLE_KSQLDB="❌🎏 Disable ksqlDB" #10
    readonly MENU_DISABLE_C3="❌💠 Disable Control Center"
    readonly MENU_DISABLE_CONDUKTOR="❌🐺 Disable Conduktor Platform"
    readonly MENU_DISABLE_RP="❌🧲 Disable Rest Proxy"
    readonly MENU_DISABLE_GRAFANA="❌📊 Disable Grafana, Prometheus and Pyroscope"
    readonly MENU_DISABLE_BROKERS="❌3️⃣ Disabling multiple brokers"
    readonly MENU_DISABLE_CONNECT_WORKERS="❌🥉 Disabling multiple connect workers"
    readonly MENU_DISABLE_KCAT="❌🐈‍⬛ Disabling kcat"
    readonly MENU_DISABLE_SQL_DATAGEN="❌🌪️ Disable SQL Datagen injection" #18

    readonly MENU_ENVIRONMENT="🔐 The environment to start (flag --environment)" #19
    readonly MENU_TAG="🎯 Confluent Platform (CP) version to use (flag --tag)"
    readonly MENU_CONNECTOR_TAG="🔗 Connector version to use (flag --connector-tag)" #21
    readonly MENU_CONNECTOR_ZIP="🤐 Connector zip to use (flag --connector-zip)"
    readonly MENU_CONNECTOR_JAR="☕ Connector jar to use (flag --connector-jar)"

    readonly MENU_CLUSTER_TYPE="🔋 The cluster type (flag --cluster-type)" #24
    readonly MENU_CLUSTER_CLOUD="🌤 The cloud provider (flag --cluster-cloud)"
    readonly MENU_CLUSTER_REGION="🗺 The Cloud region (flag --cluster-region)"
    readonly MENU_CLUSTER_ENVIRONMENT="🌐 The environment id where want your new cluster (example: txxxxx) (flag --cluster-environment)"

    readonly MENU_CLUSTER_NAME="🎰 The cluster name (flag --cluster-name)" #27
    readonly MENU_CLUSTER_CREDS="🔒 The Kafka api key and secret to use (flag --cluster-creds)"
    readonly MENU_CLUSTER_SR_CREDS="🔒 The Schema Registry api key and secret to use (flag --cluster_sr_creds)"

    stop=0
    while [ $stop != 1 ]
    do
      options=("$MENU_LETS_GO" "$MENU_ENABLE_KSQLDB" "$MENU_ENABLE_C3" "$MENU_ENABLE_CONDUKTOR" "$MENU_ENABLE_RP" "$MENU_ENABLE_GRAFANA" "$MENU_ENABLE_BROKERS" "$MENU_ENABLE_CONNECT_WORKERS" "$MENU_ENABLE_KCAT" "$MENU_ENABLE_SQL_DATAGEN" "$MENU_DISABLE_KSQLDB" "$MENU_DISABLE_C3" "$MENU_DISABLE_CONDUKTOR" "$MENU_DISABLE_RP" "$MENU_DISABLE_GRAFANA" "$MENU_DISABLE_BROKERS" "$MENU_DISABLE_CONNECT_WORKERS" "$MENU_DISABLE_KCAT" "$MENU_DISABLE_SQL_DATAGEN" "$MENU_ENVIRONMENT" "$MENU_TAG" "$MENU_CONNECTOR_TAG" "$MENU_CONNECTOR_ZIP" "$MENU_CONNECTOR_JAR" "$MENU_CLUSTER_TYPE" "$MENU_CLUSTER_CLOUD" "$MENU_CLUSTER_REGION" "$MENU_CLUSTER_ENVIRONMENT" "$MENU_CLUSTER_NAME" "$MENU_CLUSTER_CREDS" "$MENU_CLUSTER_SR_CREDS")

      connector_example=0
      get_connector_paths
      if [ "$connector_paths" != "" ]
      then
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            continue
          else
            connector_example=1
          fi
        done
      fi

      if [[ $test_file == *"ccloud"* ]]
      then
        if [[ $test_file == *"fully-managed"* ]]
        then
          unset 'options[1]'
          unset 'options[2]'
          unset 'options[3]'

          unset 'options[10]'
          unset 'options[11]'
          unset 'options[12]'

          unset 'options[8]'

          unset 'options[17]'
        
          unset 'options[19]'
          unset 'options[20]'
          unset 'options[21]'
          unset 'options[22]'
          unset 'options[23]'
        fi
        unset 'options[4]'
        unset 'options[5]'
        unset 'options[6]'
        unset 'options[7]'

        unset 'options[9]'
        unset 'options[18]'

        unset 'options[13]'
        unset 'options[14]'
        unset 'options[15]'
        unset 'options[16]'
      else
        unset 'options[24]'
        unset 'options[25]'
        unset 'options[26]'
        unset 'options[27]'
        unset 'options[28]'
        unset 'options[29]'
        unset 'options[30]'
      fi

      if [ $connector_example == 0 ]
      then
        unset 'options[19]'
        unset 'options[20]'
        unset 'options[21]'
        unset 'options[22]'
      fi
      if [ ! -z $ENABLE_KSQLDB ]
      then
        unset 'options[1]'
      else
        unset 'options[10]'
      fi
      if [ ! -z $ENABLE_CONTROL_CENTER ]
      then
        unset 'options[2]'
      else
        unset 'options[11]'
      fi
      if [ ! -z $ENABLE_CONDUKTOR ]
      then
        unset 'options[3]'
      else
        unset 'options[12]'
      fi
      if [ ! -z $ENABLE_RESTPROXY ]
      then
        unset 'options[4]'
      else
        unset 'options[13]'
      fi
      if [ ! -z $ENABLE_JMX_GRAFANA ]
      then
        unset 'options[5]'
      else
        unset 'options[14]'
      fi
      if [ ! -z $ENABLE_KAFKA_NODES ]
      then
        unset 'options[6]'
      else
        unset 'options[15]'
      fi
      if [ ! -z $ENABLE_CONNECT_NODES ]
      then
        unset 'options[7]'
      else
        unset 'options[16]'
      fi
      if [ ! -z $ENABLE_KCAT ]
      then
        unset 'options[8]'
      else
        unset 'options[17]'
      fi
      if [ ! -z $SQL_DATAGEN ]
      then
        unset 'options[9]'
      else
        unset 'options[18]'
      fi
      IFS=' ' flag_string="${flag_list[*]}"
      res=$(printf '%s\n' "${options[@]}" | fzf --multi --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🪄" --header="Select option(s) (use tab to select more than one, use ctrl-c or esc to quit)" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer --preview "echo -e \"current flag list is:\n $flag_string\"")

      if [[ $res == *"$MENU_LETS_GO"* ]]
      then
        stop=1
      fi

      if [[ $res == *"$MENU_ENABLE_KSQLDB"* ]]
      then
        flag_list+=("--enable-ksqldb")
        export ENABLE_KSQLDB=true
      fi
      if [[ $res == *"$MENU_DISABLE_KSQLDB"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-ksqldb"}")
        unset ENABLE_KSQLDB
      fi

      if [[ $res == *"$MENU_ENABLE_C3"* ]]
      then
        flag_list+=("--enable-control-center")
        export ENABLE_CONTROL_CENTER=true
      fi
      if [[ $res == *"$MENU_DISABLE_C3"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-control-center"}")
        unset ENABLE_CONTROL_CENTER
      fi

      if [[ $res == *"$MENU_ENABLE_RP"* ]]
      then
        flag_list+=("--enable-rest-proxy")
        export ENABLE_RESTPROXY=true
      fi
      if [[ $res == *"$MENU_DISABLE_RP"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-rest-proxy"}")
        unset ENABLE_RESTPROXY
      fi

      if [[ $res == *"$MENU_ENABLE_CONDUKTOR"* ]]
      then
        flag_list+=("--enable-conduktor")
        export ENABLE_CONDUKTOR=true
      fi 
      if [[ $res == *"$MENU_DISABLE_CONDUKTOR"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-conduktor"}")
        unset ENABLE_CONDUKTOR
      fi

      if [[ $res == *"$MENU_ENABLE_GRAFANA"* ]]
      then
        flag_list+=("--enable-jmx-grafana")
        export ENABLE_JMX_GRAFANA=true
      fi
      if [[ $res == *"$MENU_DISABLE_GRAFANA"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-jmx-grafana"}")
        unset ENABLE_JMX_GRAFANA
      fi

      if [[ $res == *"$MENU_ENABLE_BROKERS"* ]]
      then
        flag_list+=("--enable-multiple-broker")
        export ENABLE_KAFKA_NODES=true
      fi 
      if [[ $res == *"$MENU_DISABLE_BROKERS"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-multiple-broker"}")
        unset ENABLE_KAFKA_NODES
      fi

      if [[ $res == *"$MENU_ENABLE_CONNECT_WORKERS"* ]]
      then
        flag_list+=("--enable-multiple-connect-workers")
        export ENABLE_CONNECT_NODES=true

        # determining the docker-compose file from from test_file
        docker_compose_file=$(grep "start-environment" "$test_file" |  awk '{print $6}' | cut -d "/" -f 2 | cut -d '"' -f 1 | tail -n1 | xargs)
        docker_compose_file="${test_file_directory}/${docker_compose_file}"
        cp $docker_compose_file /tmp/playground-backup-docker-compose.yml
        yq -i '.services.connect2 = .services.connect' /tmp/playground-backup-docker-compose.yml
        yq -i '.services.connect3 = .services.connect' /tmp/playground-backup-docker-compose.yml
        cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
      fi

      if [[ $res == *"$MENU_DISABLE_CONNECT_WORKERS"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-multiple-connect-workers"}")
        unset ENABLE_CONNECT_NODES
        cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
      fi

      if [[ $res == *"$MENU_ENABLE_KCAT"* ]]
      then
        flag_list+=("--enable-kcat")
        export ENABLE_KCAT=true
      fi 
      if [[ $res == *"$MENU_DISABLE_KCAT"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-kcat"}")
        unset ENABLE_KCAT
      fi

      if [[ $res == *"$MENU_ENABLE_SQL_DATAGEN"* ]]
      then
        flag_list+=("--enable-sql-datagen")
        export SQL_DATAGEN=true
      fi
      if [[ $res == *"$MENU_DISABLE_SQL_DATAGEN"* ]]
      then
        flag_list=("${flag_list[@]/"--enable-sql-datagen"}")
        unset SQL_DATAGEN
      fi

      if [[ $res == *"$MENU_ENVIRONMENT"* ]]
      then
        options=(plaintext ccloud 2way-ssl kerberos kraft-external-plaintext kraft-plaintext ldap-authorizer-sasl-plain ldap-sasl-plain rbac-sasl-plain sasl-plain sasl-scram sasl-ssl ssl_kerberos)
        environment=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🔐" --header="select an environment" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
        
        flag_list+=("--environment=$environment")
        export PLAYGROUND_ENVIRONMENT=$environment
      fi 

      if [[ $res == *"$MENU_TAG"* ]]
      then
        tag=$(playground get-tag-list)
        if [[ $tag == *"@"* ]]
        then
          tag=$(echo "$tag" | cut -d "@" -f 2)
        fi
        flag_list+=("--tag=$tag")
        export TAG=$tag
      fi

      if [[ $res == *"$MENU_CONNECTOR_TAG"* ]]
      then
        connector_tags=""
        for connector_path in ${connector_paths//,/ }
        do
          full_connector_name=$(basename "$connector_path")
          owner=$(echo "$full_connector_name" | cut -d'-' -f1)
          name=$(echo "$full_connector_name" | cut -d'-' -f2-)

          if [ "$owner" == "java" ] || [ "$name" == "hub-components" ] || [ "$owner" == "filestream" ]
          then
            # happens when plugin is not coming from confluent hub
            continue
          fi

          ret=$(choose_connector_tag "$owner/$name")
          connector_tag=$(echo "$ret" | cut -d ' ' -f 2 | sed 's/^v//')
          
          if [ -z "$connector_tags" ]; then
            connector_tags="$connector_tag"
          else
            connector_tags="$connector_tags,$connector_tag"
          fi
        done

        connector_tag="$connector_tags"
        flag_list+=("--connector-tag=$connector_tag")
        export CONNECTOR_TAG="$connector_tag"
      fi

      if [[ $res == *"$MENU_CONNECTOR_ZIP"* ]]
      then
        connector_zip=$(playground get-zip-or-jar-with-fzf --type zip)
        if [[ $connector_zip == *"@"* ]]
        then
          connector_zip=$(echo "$connector_zip" | cut -d "@" -f 2)
        fi
        flag_list+=("--connector-zip=$connector_zip")
        export CONNECTOR_ZIP=$connector_zip
      fi

      if [[ $res == *"$MENU_CONNECTOR_JAR"* ]]
      then
        connector_jar=$(playground get-zip-or-jar-with-fzf --type jar)
        if [[ $connector_jar == *"@"* ]]
        then
          connector_jar=$(echo "$connector_jar" | cut -d "@" -f 2)
        fi
        flag_list+=("--connector-jar=$connector_jar")
        export CONNECTOR_JAR=$connector_jar
      fi

      # readonly MENU_CLUSTER_CREDS="🔒 The Kafka api key and secret to use, it should be separated with colon (example: <API_KEY>:<API_KEY_SECRET>)"
      # readonly MENU_CLUSTER_SR_CREDS="🔒 The Schema Registry api key and secret to use, it should be separated with colon (example: <SR_API_KEY>:<SR_API_KEY_SECRET>)"

      if [[ $res == *"$MENU_CLUSTER_TYPE"* ]]
      then
        options=(basic standard dedicated)
        cluster_type=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
        
        flag_list+=("--cluster-type $cluster_type")
        export CLUSTER_TYPE=$cluster_type
      fi

      if [[ $res == *"$MENU_CLUSTER_CLOUD"* ]]
      then
        options=(aws gcp azure)
        cluster_cloud=$(printf '%s\n' "${options[@]}" | fzf --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🔋" --header="select a cluster type" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" $fzf_option_wrap $fzf_option_pointer)
        
        flag_list+=("--cluster-cloud $cluster_cloud")
        export CLUSTER_CLOUD=$cluster_cloud
      fi

      if [[ $res == *"$MENU_CLUSTER_REGION"* ]]
      then
        cluster_region=$(playground get-kafka-region-list $cluster_cloud)
        
        if [[ $cluster_region == *"@"* ]]
        then
          cluster_region=$(echo "$cluster_region" | cut -d "@" -f 2)
        fi
        cluster_region=$(echo "$cluster_region" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)

        flag_list+=("--cluster-region $cluster_region")
        export CLUSTER_REGION=$cluster_region
      fi

      if [[ $res == *"$MENU_CLUSTER_ENVIRONMENT"* ]]
      then
        cluster_environment=$(playground get-ccloud-environment-list)
        
        if [[ $cluster_environment == *"@"* ]]
        then
          cluster_environment=$(echo "$cluster_environment" | cut -d "@" -f 2)
        fi
        if [[ $cluster_environment == *"/"* ]]
        then
          cluster_environment=$(echo "$cluster_environment" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
        fi
        flag_list+=("--cluster-environment $cluster_environment")
        export ENVIRONMENT=$cluster_environment
      fi

      if [[ $res == *"$MENU_CLUSTER_NAME"* ]]
      then
        cluster_name=$(playground get-ccloud-cluster-list)
        
        if [[ $cluster_name == *"@"* ]]
        then
          cluster_name=$(echo "$cluster_name" | cut -d "@" -f 2)
        fi
        if [[ $cluster_name == *"/"* ]]
        then
          cluster_name=$(echo "$cluster_name" | sed 's/[[:blank:]]//g' | cut -d "/" -f 2)
        fi
        flag_list+=("--cluster-name $cluster_name")
        export CLUSTER_NAME=$cluster_name
      fi
    done # end while loop stop
    IFS=' ' flag_list="${flag_list[*]}"

  fi # end of interactive_mode
fi

if [ "$flag_list" != "" ]
then
  if [[ $test_file == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example with flags"
  else
    log "🚀 Running example with flags"
  fi
  log "⛳ Flags used are $flag_list"
else
  if [[ $test_file == *"ccloud"* ]]
  then
    log "🚀⛅ Running ccloud example without any flags"
  else
    log "🚀 Running example without any flags"
  fi
fi
set +e
playground container kill-all
set -e
playground state set run.connector_type "$(get_connector_type | tr -d '\n')"
playground state set run.test_file "$test_file"
playground state set run.run_command "playground run -f $test_file $flag_list ${other_args[*]}"
echo "" >> "$root_folder/playground-run-history"
echo "playground run -f $test_file $flag_list ${other_args[*]}" >> "$root_folder/playground-run-history"

increment_cli_metric nb_runs
log "🚀 Number of examples ran so far: $(get_cli_metric nb_runs)"

log "####################################################"
log "🚀 Executing $filename in dir $test_file_directory"
log "####################################################"
SECONDS=0
cd $test_file_directory
function cleanup {
  if [[ -n "$enable_multiple_connect_workers" ]]
  then
    cp /tmp/playground-backup-docker-compose.yml $docker_compose_file
  fi
  rm /tmp/playground-run-command-used
  echo ""
  sleep 3
  set +e
  playground connector status
  connector_type=$(playground state get run.connector_type)
  if [ "$connector_type" == "$CONNECTOR_TYPE_ONPREM" ] || [ "$connector_type" == "$CONNECTOR_TYPE_SELF_MANAGED" ]
  then
    playground connector versions
    playground open-docs --only-show-url
  fi
  set -e
}
trap cleanup EXIT

playground generate-fzf-find-files &
generate_connector_versions > /dev/null 2>&1 &
touch /tmp/playground-run-command-used
bash $filename ${other_args[*]}
ret=$?
ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
let ELAPSED_TOTAL+=$SECONDS
set +e
# keep those lists up to date
playground generate-tag-list > /dev/null 2>&1 &
playground generate-connector-plugin-list > /dev/null 2>&1 &
playground generate-kafka-region-list > /dev/null 2>&1 &
set -e
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