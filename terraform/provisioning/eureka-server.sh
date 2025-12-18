#!/bin/bash
# Eureka Server Bootstrap Script
set -e

SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
SERVICE_USER="${service_user}"
CONFIG_HOST="${config_host}"
CONFIG_PORT="${config_port}"
GITHUB_REPO="https://github.com/Gagan772/netflix-oss-project.git"

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting bootstrap for $SERVICE_NAME at $(date)"

# System Setup
apt-get update -y && apt-get install -y openjdk-17-jdk maven git curl

# Wait for Config Server
echo "Waiting for Config Server..."
for i in {1..60}; do
    curl -s http://$CONFIG_HOST:$CONFIG_PORT/actuator/health | grep -q "UP" && break
    sleep 10
done

# Create service user and directories
useradd -r -m -s /bin/bash $SERVICE_USER || true
mkdir -p /opt/$SERVICE_NAME /var/log/$SERVICE_NAME

# Clone and build
cd /tmp
git clone $GITHUB_REPO netflix-oss
cd netflix-oss/services/$SERVICE_NAME
mvn clean package -DskipTests -q
cp target/*.jar /opt/$SERVICE_NAME/app.jar

# Set permissions
chown -R $SERVICE_USER:$SERVICE_USER /opt/$SERVICE_NAME /var/log/$SERVICE_NAME

# Create systemd service
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Netflix OSS Eureka Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/opt/$SERVICE_NAME
ExecStart=/usr/bin/java -Xms256m -Xmx512m -jar /opt/$SERVICE_NAME/app.jar --server.port=$SERVICE_PORT --spring.config.import=optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable $SERVICE_NAME && systemctl start $SERVICE_NAME

echo "Bootstrap complete for $SERVICE_NAME at $(date)"
