container="${args[--container]}"
port="${args[--port]}"
destination="${args[--destination]}"
action="${args[--action]}"

set +e
docker exec $container type iptables > /dev/null 2>&1
if [ $? != 0 ]
then
    logwarn "iptables is not installed on container $container, attempting to install it"

    DIR_CLI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    dir1=$(echo ${DIR_CLI%/*})
    root_folder=$(echo ${dir1%/*})
    IGNORE_CHECK_FOR_DOCKER_COMPOSE=true
    source $root_folder/scripts/utils.sh

    if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
    then
      docker exec --privileged --user root $container bash -c "yum -y install --disablerepo='Confluent*' iptables"
    else
      docker exec --privileged --user root $container bash -c "apt-get update && echo iptables | xargs -n 1 apt-get install --force-yes -y && rm -rf /var/lib/apt/lists/*"
    fi
fi
docker exec $container type iptables > /dev/null 2>&1
if [ $? != 0 ]
then
    logerror "❌ iptables could not be installed"
    exit 1
fi
set -e

ip_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

function get_container_ip() {
    local container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1")
    if [ $? -eq 0 ]
    then
        echo "$container_ip"
    fi
}

function get_ip_by_nslookup() {
    local ip_address=$(nslookup "$1" | awk '/^Address: / { print $2 }')
    if [ $? -eq 0 ]
    then
        echo "$ip_address"
    fi
}

ip=""
if [[ $destination =~ $ip_pattern ]]
then
    ip=$destination
else
    ip_address=$(get_container_ip "$destination")
    if [[ -n $ip_address ]]
    then
        ip=$ip_address
    else
        log "🌐 Using nslookup to get IP address..."
        ip_address=$(get_ip_by_nslookup "$destination")
        if [[ -n $ip_address ]]
        then
            ip=$ip_address
        else
            logerror "❌ Unable to retrieve IP address for $destination using nslookup"
            exit 1
        fi
    fi
fi

case "${action}" in
    start)
        action="A"
        if [[ -n "$port" ]]
        then
            log "🚫 Blocking traffic on container ${container} and port ${port} for destination ${destination} (${ip})"
        else
            log "🚫 Blocking traffic on container ${container} for all ports for destination ${destination} (${ip})"
        fi
    ;;
    stop)
        action="D"

        if [[ -n "$port" ]]
        then
            log "🟢 Unblocking traffic on container ${container} and port ${port} for destination ${destination} (${ip})"
        else
            log "🟢 Unblocking traffic on container ${container} for all ports from destination ${destination} (${ip})"
        fi
    ;;
    *)
        logerror "should not happen"
        exit 1
    ;;
esac

if [[ -n "$port" ]]
then
  docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} --dport ${port} -j DROP"
else
  docker exec --privileged --user root ${container} bash -c "iptables -${action} INPUT -p tcp -s ${ip} -j DROP"
fi

log "Output of command iptables-save"
docker exec --privileged --user root ${container} bash -c "iptables-save"
