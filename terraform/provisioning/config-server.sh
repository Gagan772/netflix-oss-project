#!/bin/bash
# =============================================================================
# Config Server Bootstrap Script
# =============================================================================

set -e

# Variables from Terraform
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
SERVICE_USER="${service_user}"
CA_CERT='${ca_cert}'

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting bootstrap for $SERVICE_NAME at $(date)"

# =============================================================================
# System Setup
# =============================================================================

echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "Installing required packages..."
apt-get install -y openjdk-17-jdk maven git curl wget unzip

# Verify Java installation
java -version
mvn -version

# =============================================================================
# Create Service User
# =============================================================================

echo "Creating service user: $SERVICE_USER"
useradd -r -m -s /bin/bash $SERVICE_USER || true

# =============================================================================
# Create Directory Structure
# =============================================================================

echo "Creating directory structure..."
mkdir -p /opt/$SERVICE_NAME
mkdir -p /opt/$SERVICE_NAME/certs
mkdir -p /etc/$SERVICE_NAME
mkdir -p /var/log/$SERVICE_NAME

# =============================================================================
# Clone and Build Application
# =============================================================================

echo "Cloning application code..."
cd /tmp

# Create the service code directly (embedded from Terraform)
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/configserver
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/config-repo

# Create pom.xml
cat > /tmp/netflix-oss/services/$SERVICE_NAME/pom.xml << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
        <relativePath/>
    </parent>

    <groupId>com.netflix.oss</groupId>
    <artifactId>config-server</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    <name>config-server</name>

    <properties>
        <java.version>17</java.version>
        <spring-cloud.version>2023.0.0</spring-cloud.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-config-server</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
    </dependencies>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.cloud</groupId>
                <artifactId>spring-cloud-dependencies</artifactId>
                <version>$${spring-cloud.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
POMEOF

# Create main application class
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/configserver/ConfigServerApplication.java << 'JAVAEOF'
package com.netflix.oss.configserver;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.config.server.EnableConfigServer;

@SpringBootApplication
@EnableConfigServer
public class ConfigServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(ConfigServerApplication.class, args);
    }
}
JAVAEOF

# Create application.yml
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/application.yml << 'YAMLEOF'
server:
  port: 8888

spring:
  application:
    name: config-server
  profiles:
    active: native
  cloud:
    config:
      server:
        native:
          search-locations: classpath:/config-repo

management:
  endpoints:
    web:
      exposure:
        include: health,info,env
  endpoint:
    health:
      show-details: always
YAMLEOF

# Create config-repo files
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/config-repo/application.yml << 'CFGEOF'
spring:
  cloud:
    config:
      enabled: true

management:
  endpoints:
    web:
      exposure:
        include: health,info,env,refresh
  endpoint:
    health:
      show-details: always

logging:
  level:
    root: INFO
    com.netflix.oss: DEBUG
CFGEOF

# Build application
echo "Building application..."
cd /tmp/netflix-oss/services/$SERVICE_NAME
mvn clean package -DskipTests -q

# Copy JAR to deployment location
echo "Deploying application..."
cp target/*.jar /opt/$SERVICE_NAME/app.jar

# =============================================================================
# Store CA Certificate
# =============================================================================

echo "Storing CA certificate..."
cat > /opt/$SERVICE_NAME/certs/ca.crt << 'CAEOF'
$CA_CERT
CAEOF

# =============================================================================
# Set Permissions
# =============================================================================

echo "Setting permissions..."
chown -R $SERVICE_USER:$SERVICE_USER /opt/$SERVICE_NAME
chown -R $SERVICE_USER:$SERVICE_USER /etc/$SERVICE_NAME
chown -R $SERVICE_USER:$SERVICE_USER /var/log/$SERVICE_NAME
chmod 600 /opt/$SERVICE_NAME/certs/*

# =============================================================================
# Create Systemd Service
# =============================================================================

echo "Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Netflix OSS Config Server
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/opt/$SERVICE_NAME
ExecStart=/usr/bin/java -jar /opt/$SERVICE_NAME/app.jar
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

Environment="JAVA_OPTS=-Xms256m -Xmx512m"
Environment="SERVER_PORT=$SERVICE_PORT"

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# Start Service
# =============================================================================

echo "Starting service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Wait for service to be healthy
echo "Waiting for service to be healthy..."
for i in {1..60}; do
    if curl -s http://localhost:$SERVICE_PORT/actuator/health | grep -q "UP"; then
        echo "Service is healthy!"
        break
    fi
    echo "Waiting for service... attempt $i"
    sleep 5
done

echo "Bootstrap complete for $SERVICE_NAME at $(date)"
