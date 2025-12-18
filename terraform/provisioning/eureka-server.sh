#!/bin/bash
# =============================================================================
# Eureka Server Bootstrap Script
# =============================================================================

set -e

# Variables from Terraform
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
SERVICE_USER="${service_user}"
CONFIG_HOST="${config_host}"
CONFIG_PORT="${config_port}"
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

java -version
mvn -version

# =============================================================================
# Wait for Config Server
# =============================================================================

echo "Waiting for Config Server to be available..."
for i in {1..60}; do
    if curl -s http://$CONFIG_HOST:$CONFIG_PORT/actuator/health | grep -q "UP"; then
        echo "Config Server is available!"
        break
    fi
    echo "Waiting for Config Server... attempt $i"
    sleep 10
done

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

echo "Creating application code..."
cd /tmp

mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/eurekaserver
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources

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
    <artifactId>eureka-server</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    <name>eureka-server</name>

    <properties>
        <java.version>17</java.version>
        <spring-cloud.version>2023.0.0</spring-cloud.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-config</artifactId>
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
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/eurekaserver/EurekaServerApplication.java << 'JAVAEOF'
package com.netflix.oss.eurekaserver;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;

@SpringBootApplication
@EnableEurekaServer
public class EurekaServerApplication {
    public static void main(String[] args) {
        SpringApplication.run(EurekaServerApplication.class, args);
    }
}
JAVAEOF

# Create application.yml
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/application.yml << YAMLEOF
spring:
  application:
    name: eureka-server
  config:
    import: optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT

server:
  port: $SERVICE_PORT

eureka:
  instance:
    hostname: localhost
    prefer-ip-address: true
  client:
    register-with-eureka: false
    fetch-registry: false
    service-url:
      defaultZone: http://localhost:$SERVICE_PORT/eureka/
  server:
    enable-self-preservation: false
    eviction-interval-timer-in-ms: 5000

management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: always
YAMLEOF

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
chmod 600 /opt/$SERVICE_NAME/certs/* 2>/dev/null || true

# =============================================================================
# Create Systemd Service
# =============================================================================

echo "Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Netflix OSS Eureka Server
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
Environment="CONFIG_HOST=$CONFIG_HOST"
Environment="CONFIG_PORT=$CONFIG_PORT"
Environment="EUREKA_HOST=localhost"

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
