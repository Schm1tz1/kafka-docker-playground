#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-sqlserver-source
if [ ! -f ${PWD}/sqljdbc_12.2/enu/mssql-jdbc-12.2.0.jre11.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-12.2.0.jre11.jar"
     curl -L https://go.microsoft.com/fwlink/?linkid=2222954 -o sqljdbc_12.2.0.0_enu.tar.gz
     tar xvfz sqljdbc_12.2.0.0_enu.tar.gz
     rm -f sqljdbc_12.2.0.0_enu.tar.gz
fi
cd -

cd ${DIR}/ssl
if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

rm -f mssql.pem
rm -f mssql.key

#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-security?view=sql-server-ver15
#https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-encrypted-connections?view=sql-server-ver15&preserve-view=true#client-initiated-encryption
log "Create a self-signed certificate"
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} openssl req -x509 -nodes -newkey rsa:2048 -subj '/CN=sqlserver' -keyout /tmp/mssql.key -out /tmp/mssql.pem -days 365

if [[ "$OSTYPE" == "darwin"* ]]
then
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

log "Creating JKS from pem files"
rm -f truststore.jks
docker run --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} keytool -importcert -alias MSSQLCACert -noprompt -file /tmp/mssql.pem -keystore /tmp/truststore.jks -storepass confluent

if [[ "$OSTYPE" == "darwin"* ]]
then
    # not running with github actions
    # workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
    chmod -R a+rw .
else
    # on CI, docker is run as runneradmin user, need to use sudo
    ls -lrt
    sudo chmod -R a+rw .
    ls -lrt
fi

cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft-ssl.yml"

log "Create table"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL
);
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Sally','Thomas','sally.thomas@acme.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('George','Bailey','gbailey@foobar.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Edward','Walker','ed@walker.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Anne','Kretchmar','annek@noanswer.org');
GO
EOF

# https://docs.microsoft.com/en-us/sql/connect/jdbc/connecting-with-ssl-encryption?view=sql-server-ver16
log "Creating JDBC SQL Server (with Microsoft driver) source connector"
playground connector create-or-update --connector sqlserver-source-ssl << EOF
{
                "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                "tasks.max": "1",
                "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB;encrypt=true;trustServerCertificate=false;trustStore=/tmp/truststore.jks;trustStorePassword=confluent;",
                "connection.user": "sa",
                "connection.password": "Password!",
                "table.whitelist": "customers",
                "mode": "incrementing",
                "incrementing.column.name": "id",
                "topic.prefix": "sqlserver-",
                "validate.non.null":"false",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true"
          }
EOF

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic sqlserver-customers"
playground topic consume --topic sqlserver-customers --min-expected-messages 5 --timeout 60
