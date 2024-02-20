# Splunk Source connector



## Objective

Quickly test [Splunk Source](https://docs.confluent.io/current/connect/kafka-connect-splunk/splunk-source/index.html#quick-start) connector.


## How to run

Simply run:

```
$ playground run -f splunk<use tab key to activate fzf completion (see https://kafka-docker-playground.io/#/cli?id=%e2%9a%a1-setup-completion), otherwise use full path, or correct relative path>
```

## Details of what the script is doing

Creating Splunk source connector

```bash
$ curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.SplunkHttpSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "splunk-source",
                    "splunk.collector.index.default": "default-index",
                    "splunk.port": "8889",
                    "splunk.ssl.key.store.path": "/tmp/keystore.jks",
                    "splunk.ssl.key.store.password": "confluent",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/splunk-source/config | jq .
```

Simulate an application sending data to the connector

```bash
$ curl -k -X POST https://localhost:8889/services/collector/event -d '{"event":"from curl"}'
```

Verifying topic `splunk-source`

```bash
playground topic consume --topic splunk-source --min-expected-messages 1 --timeout 60
```

Results:

```json
{
    "event": {
        "string": "from curl"
    },
    "host": {
        "string": "172.20.0.1"
    },
    "index": {
        "string": "default-index"
    },
    "source": null,
    "sourcetype": null,
    "time": {
        "long": 1571932581452
    }
}
```


N.B: Control Center is reachable at [http://127.0.0.1:9021](http://127.0.0.1:9021])
