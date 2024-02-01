connector="${args[--connector]}"
wait_for_zero_lag="${args[--wait-for-zero-lag]}"
verbose="${args[--verbose]}"

get_connect_url_and_security

if [[ ! -n "$connector" ]]
then
    connector=$(playground get-connector-list)
    if [ "$connector" == "" ]
    then
        logerror "💤 No connector is running !"
        exit 1
    fi
fi

get_security_broker "--command-config"

declare -A prev_lags
prev_lags=()

function show_output () {
  while read line; do
    arr=($line)
    topic=${arr[1]}
    partition=${arr[2]}
    current_offset=${arr[3]}
    end_offset=${arr[4]}
    lag=${arr[5]}
    prev_lag=${prev_lags["${topic}_${partition}"]}
    compare_line=""
    compare_action=""
    if [[ "$total_lag" =~ ^[0-9]+$ ]]
    then
      if [[ "$prev_lag" =~ ^[0-9]+$ ]]
      then
        if [ $lag -lt $prev_lag ]
        then
          compare_line="🔻 $(($prev_lag - $lag))"
          compare_action="up"
        elif [ $lag -eq $prev_lag ]
        then
          compare_line="🔸"
          compare_action="same"
        else
          compare_line="🔺 $(($lag - $prev_lag))"
          compare_action="down"
        fi
      fi
    fi
    prev_lags["${topic}_${partition}"]=$lag
    if [ "$compare_line" != "" ]
    then
      case "${compare_action}" in
        up)
          printf "\033[32mtopic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s %s\033[0m\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$compare_line"
        ;;
        down)
          printf "\033[31mtopic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s %s\033[0m\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$compare_line"
        ;;
        *)
          printf "topic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s %s\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag" "$compare_line"
        ;;
      esac
    else
      printf "topic: %-10s partition: %-3s current-offset: %-10s end-offset: %-10s lag: %-10s\n" "$topic" "$partition" "$current_offset" "$end_offset" "$lag"
    fi
  done < <(cat "$lag_output" | grep -v PARTITION | sed '/^$/d' | sort -k2n)
}


tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
lag_output=$tmp_dir/lag_output

function handle_signal {
  echo "Stopping..."
  stop=1
}
# Set the signal handler
trap handle_signal SIGINT

items=($connector)
length=${#items[@]}
if ((length > 1))
then
    if [[ -n "$wait_for_zero_lag" ]]
    then
      logerror "❌ --connector shhould be set when used with --wait-for-zero-lag"
      exit 1
    fi

    log "✨ --connector flag was not provided, applying command to all connectors"
fi
for connector in ${items[@]}
do
  type=$(curl -s $security "$connect_url/connectors/$connector/status" | jq -r '.type')
  if [ "$type" != "sink" ]
  then
    logwarn "⏭️ Skipping $type connector $connector, it must be a sink to show the lag"
    continue 
  fi

  if [[ -n "$verbose" ]]
  then
      log "🐞 CLI command used"
      echo "kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security"
  fi

  CHECK_INTERVAL=5
  SECONDS=0
  prev_lag=0
  stop=0

  while [ $stop != 1 ]
  do
    docker exec $container kafka-consumer-groups --bootstrap-server broker:9092 --group connect-$connector --describe $security | grep -v PARTITION | sed '/^$/d' &> $lag_output

    if grep -q "Warning" $lag_output
    then
      logwarn "🐢 consumer group for connector $connector is rebalancing"
      cat $lag_output
      sleep $CHECK_INTERVAL
      continue
    fi

    set +e
    lag_not_set=$(cat "$lag_output" | awk -F" " '{ print $6 }' | grep "-")

    if [ ! -z "$lag_not_set" ]
    then
      logwarn "🐢 consumer lag for connector $connector is not available"
      show_output
      sleep $CHECK_INTERVAL
    else
      total_lag=$(cat "$lag_output" | grep -v "PARTITION" | awk -F" " '{sum+=$6;} END{print sum;}')

      if [[ "$total_lag" =~ ^[0-9]+$ ]]
      then
        if [ $total_lag -ne 0 ]
        then
          compare=""
          if [[ "$prev_lag" =~ ^[0-9]+$ ]]
          then
            if [ $prev_lag != 0 ]
            then
              if [ $total_lag -lt $prev_lag ]
              then
                compare="🔻 $(($prev_lag - $total_lag))"
              elif [ $total_lag -eq $prev_lag ]
              then
                compare="🔸"
              else
                compare="🔺 $(($total_lag - $prev_lag))"
              fi
            fi
          fi
          if [ "$compare" != "" ]
          then
            log "🐢 consumer lag for connector $connector is $total_lag $compare (press ctrl-c to stop)"
          else
            log "🐢 consumer lag for connector $connector is $total_lag"
          fi
          show_output
          
          prev_lag=$total_lag
          sleep $CHECK_INTERVAL
        else
          if [[ ! -n "$wait_for_zero_lag" ]]
          then
            log "🏁 consumer lag for connector $connector is 0 !"
          else
            ELAPSED="took: $((($SECONDS / 60) % 60))min $(($SECONDS % 60))sec"
            log "🏁 consumer lag for connector $connector is 0 ! $ELAPSED"
          fi
          show_output
          break
        fi
      fi
    fi
  done
done