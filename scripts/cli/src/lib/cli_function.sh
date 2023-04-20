function get_environment_used() {
  if [ ! -f /tmp/playground-command ]
  then
    echo "error"
    return
  fi

  patterns=("environment/2way-ssl" "environment/sasl-ssl" "environment/rbac-sasl-plain" "environment/kerberos" "environment/ssl_kerberos" "environment/ldap-authorizer-sasl-plain" "environment/sasl-plain" "environment/ldap-sasl-plain" "environment/sasl-scram" "environment/mdc-plaintext" "environment/mdc-sasl-plain" "environment/mdc-kerberos")

  for pattern in "${patterns[@]}"; do
    if grep -q "$pattern" /tmp/playground-command; then
      echo "${pattern#*/}"
      return
    fi
  done

  echo "plaintext"
}

function get_connect_url_and_security() {
  environment=`get_environment_used`

  if [ "$environment" == "error" ]
  then
    logerror "File containing restart command /tmp/playground-command does not exist!"
    exit 1 
  fi
  connect_url="http://localhost:8083"
  security=""
  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      connect_url="https://localhost:8083"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="--cert $DIR_CLI/../../environment/$environment/security/connect.certificate.pem --key $DIR_CLI/../../environment/$environment/security/connect.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="-u connectorSubmitter:connectorSubmitter"
  fi

  echo "$connect_url@$security"
}

function get_sr_url_and_security() {
  environment=`get_environment_used`

  if [ "$environment" == "error" ]
  then
    logerror "File containing restart command /tmp/playground-command does not exist!"
    exit 1 
  fi

  sr_url="http://localhost:8081"
  security_sr=""

  if [[ "$environment" == "sasl-ssl" ]] || [[ "$environment" == "2way-ssl" ]]
  then
      sr_url="https://localhost:8081"
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="--cert $DIR_CLI/../../environment/$environment/security/schema-registry.certificate.pem --key $DIR_CLI/../../environment/$environment/security/schema-registry.key --tlsv1.2 --cacert $DIR_CLI/../../environment/$environment/security/snakeoil-ca-1.crt"
  elif [[ "$environment" == "rbac-sasl-plain" ]]
  then
      DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

      security="-u superUser:superUser"
  fi

  echo "$sr_url@$security"
}

function get_security_broker() {
  config_file_name="$1"
  environment=`get_environment_used`

  if [ "$environment" == "error" ]
  then
    logerror "File containing restart command /tmp/playground-command does not exist!"
    exit 1 
  fi

  container="broker"
  security=""
  if [[ "$environment" == "kerberos" ]] || [[ "$environment" == "ssl_kerberos" ]]
  then
      container="client"
      security="$config_file_name /etc/kafka/consumer.properties"

      docker exec -i client kinit -k -t /var/lib/secret/kafka-connect.key connect
  elif [ "$environment" == "ldap-authorizer-sasl-plain" ]
  then
      security="$config_file_name /service/kafka/users/kafka.properties"
  elif [ "$environment" == "ldap-sasl-plain" ] || [ "$environment" == "sasl-plain" ] || [ "$environment" == "sasl-scram" ]
  then
      security="$config_file_name /tmp/client.properties"
  elif [ "$environment" != "plaintext" ]
  then
      security="$config_file_name /etc/kafka/secrets/client_without_interceptors.config"
  fi
  echo "$container@$security"
}

function get_connector_list() {
  ret=$(get_connect_url_and_security)

  connect_url=$(echo "$ret" | cut -d "@" -f 1)
  security=$(echo "$ret" | cut -d "@" -f 2)

  curl $security -s "$connect_url/connectors" | jq -r '.[]' | tr '\n' ' ' | sed -e 's/[[:space:]]*$//'
}

function get_fzf_version() {
    version=$(fzf --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | cut -d " " -f 1)
    echo "$version"
}

function get_examples_list_with_fzf() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
  else
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
  fi
}

function get_examples_list_with_fzf_without_repro() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi

  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
  else
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
  fi
}

function get_examples_list_with_fzf_without_repro_sink_only() {
  DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
  dir1=$(echo ${DIR_CLI%/*})
  dir2=$(echo ${dir1%/*})

  cur="$1"

  fzf_version=$(get_fzf_version)
  if version_gt $fzf_version "0.38"
  then
    fzf_option_wrap="--preview-window=40%,wrap"
    fzf_option_pointer="--pointer=👉"
    fzf_option_rounded="--border=rounded"
  else
    fzf_options=""
    fzf_option_pointer=""
    fzf_option_rounded=""
  fi
  
  if [[ $(type -f bat 2>&1) =~ "not found" ]]
  then
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'cat {}');echo "$cur@$res"
  else
    res=$(find $dir2 -name \*.sh ! -name 'stop.sh' -path '*/connect-*-sink/*' ! -path '*/scripts/*' ! -path '*/docs-examples/*' ! -path '*/sample-sql-scripts/*' ! -path '*/ora-setup-scripts/*' ! -path '*/reproduction-models/*' | fzf --query "$cur" --margin=1%,1%,1%,1% $fzf_option_rounded --info=inline --prompt="🍺" --header="ctrl-c or esc to quit" --color="bg:-1,bg+:-1,info:#BDBB72,border:#FFFFFF,spinner:0,hl:#beb665,fg:#00f7f7,header:#5CC9F5,fg+:#beb665,pointer:#E12672,marker:#5CC9F5,prompt:#98BEDE" --delimiter / --with-nth "-3,-2,-1" $fzf_option_wrap $fzf_option_pointer --preview 'bat --style=plain --color=always --line-range :500 {}');echo "$cur@$res"
  fi
}

function filter_not_mdc_environment() {
  environment=`get_environment_used`

  if [ "$environment" == "error" ]
  then
    logerror "File containing restart command /tmp/playground-command does not exist!"
    exit 1 
  fi

  if [[ "$environment" == "mdc"* ]]
  then
    echo "$environment is not supported with this command !"
  fi
}