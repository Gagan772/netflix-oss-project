#!/bin/bash
# User BFF Bootstrap Script (mTLS Client)
set -e

SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
SERVICE_USER="${service_user}"
CONFIG_HOST="${config_host}"
CONFIG_PORT="${config_port}"
EUREKA_HOST="${eureka_host}"
EUREKA_PORT="${eureka_port}"
MIDDLEWARE_HOST="${middleware_host}"
MIDDLEWARE_PORT="${middleware_port}"
CA_CERT='${ca_cert}'
CLIENT_CERT='${client_cert}'
CLIENT_KEY='${client_key}'
GITHUB_REPO="https://github.com/Gagan772/netflix-oss-project.git"

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting bootstrap for $SERVICE_NAME at $(date)"

# System Setup
apt-get update -y && apt-get install -y openjdk-17-jdk maven git curl

# Wait for Middleware
echo "Waiting for Middleware..."
for i in {1..60}; do
    if curl -sk https://$MIDDLEWARE_HOST:$MIDDLEWARE_PORT/actuator/health 2>/dev/null | grep -q "UP"; then break; fi
    sleep 10
done

# Create service user and directories
useradd -r -m -s /bin/bash $SERVICE_USER || true
mkdir -p /opt/$SERVICE_NAME /opt/$SERVICE_NAME/certs /var/log/$SERVICE_NAME

# Setup mTLS certificates
echo "$CA_CERT" > /opt/$SERVICE_NAME/certs/ca.crt
echo "$CLIENT_CERT" > /opt/$SERVICE_NAME/certs/client.crt
echo "$CLIENT_KEY" > /opt/$SERVICE_NAME/certs/client.key

# Create PKCS12 keystore and truststore
cd /opt/$SERVICE_NAME/certs
openssl pkcs12 -export -in client.crt -inkey client.key -out client-keystore.p12 -name userbff -password pass:changeit
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
Description=Netflix OSS User BFF Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/opt/$SERVICE_NAME
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar /opt/$SERVICE_NAME/app.jar \
  --server.port=$SERVICE_PORT \
  --spring.config.import=optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT \
  --eureka.client.service-url.defaultZone=http://$EUREKA_HOST:$EUREKA_PORT/eureka/ \
  --middleware.url=https://$MIDDLEWARE_HOST:$MIDDLEWARE_PORT \
  --middleware.ssl.trust-store=/opt/$SERVICE_NAME/certs/truststore.p12 \
  --middleware.ssl.trust-store-password=changeit \
  --middleware.ssl.key-store=/opt/$SERVICE_NAME/certs/client-keystore.p12 \
  --middleware.ssl.key-store-password=changeit \
  --middleware.ssl.key-password=changeit
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable $SERVICE_NAME && systemctl start $SERVICE_NAME

echo "Bootstrap complete for $SERVICE_NAME at $(date)"
