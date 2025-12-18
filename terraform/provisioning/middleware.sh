#!/bin/bash
# Middleware Bootstrap Script (mTLS Server)
set -e

SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
SERVICE_USER="${service_user}"
CONFIG_HOST="${config_host}"
CONFIG_PORT="${config_port}"
EUREKA_HOST="${eureka_host}"
EUREKA_PORT="${eureka_port}"
BACKEND_HOST="${backend_host}"
BACKEND_PORT="${backend_port}"
CA_CERT='${ca_cert}'
SERVER_CERT='${server_cert}'
SERVER_KEY='${server_key}'
GITHUB_REPO="https://github.com/Gagan772/netflix-oss-project.git"

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting bootstrap for $SERVICE_NAME at $(date)"

# System Setup
apt-get update -y && apt-get install -y openjdk-17-jdk maven git curl

# Wait for Backend
echo "Waiting for Backend..."
for i in {1..60}; do
    curl -s http://$BACKEND_HOST:$BACKEND_PORT/actuator/health | grep -q "UP" && break
    sleep 10
done

# Create service user and directories
useradd -r -m -s /bin/bash $SERVICE_USER || true
mkdir -p /opt/$SERVICE_NAME /opt/$SERVICE_NAME/certs /var/log/$SERVICE_NAME

# Setup mTLS certificates
echo "$CA_CERT" > /opt/$SERVICE_NAME/certs/ca.crt
echo "$SERVER_CERT" > /opt/$SERVICE_NAME/certs/server.crt
echo "$SERVER_KEY" > /opt/$SERVICE_NAME/certs/server.key

# Create PKCS12 keystore and truststore
cd /opt/$SERVICE_NAME/certs
openssl pkcs12 -export -in server.crt -inkey server.key -out server-keystore.p12 -name middleware -password pass:changeit
keytool -import -trustcacerts -alias ca -file ca.crt -keystore truststore.p12 -storetype PKCS12 -storepass changeit -noprompt

# Clone and build
cd /tmp
git clone $GITHUB_REPO netflix-oss
cd netflix-oss/services/$SERVICE_NAME
mvn clean package -DskipTests -q
cp target/*.jar /opt/$SERVICE_NAME/app.jar

# Set permissions
chown -R $SERVICE_USER:$SERVICE_USER /opt/$SERVICE_NAME /var/log/$SERVICE_NAME
chmod 600 /opt/$SERVICE_NAME/certs/*.key /opt/$SERVICE_NAME/certs/*.p12

# Create systemd service
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Netflix OSS Middleware Service (mTLS)
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/opt/$SERVICE_NAME
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar /opt/$SERVICE_NAME/app.jar \
  --server.port=$SERVICE_PORT \
  --server.ssl.enabled=true \
  --server.ssl.key-store=/opt/$SERVICE_NAME/certs/server-keystore.p12 \
  --server.ssl.key-store-password=changeit \
  --server.ssl.key-store-type=PKCS12 \
  --server.ssl.client-auth=need \
  --server.ssl.trust-store=/opt/$SERVICE_NAME/certs/truststore.p12 \
  --server.ssl.trust-store-password=changeit \
  --server.ssl.trust-store-type=PKCS12 \
  --spring.config.import=optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT \
  --eureka.client.service-url.defaultZone=http://$EUREKA_HOST:$EUREKA_PORT/eureka/ \
  --backend.url=http://$BACKEND_HOST:$BACKEND_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable $SERVICE_NAME && systemctl start $SERVICE_NAME

echo "Bootstrap complete for $SERVICE_NAME at $(date)"
