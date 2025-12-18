#!/bin/bash
# =============================================================================
# Middleware Bootstrap Script (with mTLS Server)
# =============================================================================

set -e

# Variables from Terraform
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
# Wait for Dependencies
# =============================================================================

echo "Waiting for Backend to be available..."
for i in {1..60}; do
    if curl -s http://$BACKEND_HOST:$BACKEND_PORT/actuator/health | grep -q "UP"; then
        echo "Backend is available!"
        break
    fi
    echo "Waiting for Backend... attempt $i"
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
# Setup PKI/Certificates for mTLS
# =============================================================================

echo "Setting up certificates for mTLS..."

# Store CA certificate
cat > /opt/$SERVICE_NAME/certs/ca.crt << 'CAEOF'
$CA_CERT
CAEOF

# Store server certificate
cat > /opt/$SERVICE_NAME/certs/server.crt << 'SRVEOF'
$SERVER_CERT
SRVEOF

# Store server key
cat > /opt/$SERVICE_NAME/certs/server.key << 'KEYEOF'
$SERVER_KEY
KEYEOF

# Create PKCS12 keystore from server cert and key
echo "Creating server keystore..."
openssl pkcs12 -export \
    -in /opt/$SERVICE_NAME/certs/server.crt \
    -inkey /opt/$SERVICE_NAME/certs/server.key \
    -out /opt/$SERVICE_NAME/certs/server-keystore.p12 \
    -name middleware \
    -passout pass:changeit

# Create truststore with CA certificate
echo "Creating truststore..."
keytool -import \
    -file /opt/$SERVICE_NAME/certs/ca.crt \
    -alias rootca \
    -keystore /opt/$SERVICE_NAME/certs/truststore.p12 \
    -storetype PKCS12 \
    -storepass changeit \
    -noprompt

# =============================================================================
# Clone and Build Application
# =============================================================================

echo "Creating application code..."
cd /tmp

mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/middleware/controller
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/middleware/service
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
    <artifactId>middleware</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    <name>middleware</name>

    <properties>
        <java.version>17</java.version>
        <spring-cloud.version>2023.0.0</spring-cloud.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.cloud</groupId>
            <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
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
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/middleware/MiddlewareApplication.java << 'JAVAEOF'
package com.netflix.oss.middleware;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

@SpringBootApplication
@EnableDiscoveryClient
public class MiddlewareApplication {
    public static void main(String[] args) {
        SpringApplication.run(MiddlewareApplication.class, args);
    }
}
JAVAEOF

# Create backend service
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/middleware/service/BackendService.java << 'JAVAEOF'
package com.netflix.oss.middleware.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

@Service
public class BackendService {

    private static final Logger logger = LoggerFactory.getLogger(BackendService.class);

    private final RestTemplate restTemplate;
    private final String backendUrl;

    public BackendService(@Value("${backend.url}") String backendUrl) {
        this.restTemplate = new RestTemplate();
        this.backendUrl = backendUrl;
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> callBackend(Map<String, Object> payload) {
        logger.info("Calling backend at: {}", backendUrl);
        
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(payload, headers);
            
            ResponseEntity<Map> response = restTemplate.postForEntity(
                    backendUrl + "/api/backend/process",
                    request,
                    Map.class
            );
            
            logger.info("Backend response status: {}", response.getStatusCode());
            return response.getBody();
        } catch (Exception e) {
            logger.error("Error calling backend: {}", e.getMessage(), e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("backendError", e.getMessage());
            errorResponse.put("servedBy", "middleware-fallback");
            return errorResponse;
        }
    }
}
JAVAEOF

# Create controller
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/middleware/controller/MiddlewareController.java << 'JAVAEOF'
package com.netflix.oss.middleware.controller;

import com.netflix.oss.middleware.service.BackendService;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.security.cert.X509Certificate;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/mw")
public class MiddlewareController {

    private static final Logger logger = LoggerFactory.getLogger(MiddlewareController.class);

    private final BackendService backendService;

    public MiddlewareController(BackendService backendService) {
        this.backendService = backendService;
    }

    @PostMapping("/forward")
    public ResponseEntity<Map<String, Object>> forward(
            @RequestBody Map<String, Object> payload,
            HttpServletRequest request) {
        
        logger.info("Middleware received request");
        
        Map<String, Object> response = new HashMap<>();
        
        X509Certificate[] certs = (X509Certificate[]) request.getAttribute("jakarta.servlet.request.X509Certificate");
        
        boolean mtlsVerified = false;
        String clientCN = "unknown";
        
        if (certs != null && certs.length > 0) {
            X509Certificate clientCert = certs[0];
            clientCN = extractCN(clientCert.getSubjectX500Principal().getName());
            mtlsVerified = true;
            logger.info("mTLS verified! Client CN: {}", clientCN);
        } else {
            logger.warn("No client certificate provided");
        }
        
        response.put("mtlsVerified", mtlsVerified);
        response.put("clientCN", clientCN);
        response.put("middlewareProcessed", true);
        
        Map<String, Object> backendResponse = backendService.callBackend(payload);
        response.putAll(backendResponse);
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "middleware");
        response.put("ssl", "enabled");
        return ResponseEntity.ok(response);
    }

    private String extractCN(String dn) {
        for (String part : dn.split(",")) {
            String trimmed = part.trim();
            if (trimmed.startsWith("CN=")) {
                return trimmed.substring(3);
            }
        }
        return dn;
    }
}
JAVAEOF

# Create application.yml
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/application.yml << YAMLEOF
spring:
  application:
    name: middleware
  config:
    import: optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT

server:
  port: $SERVICE_PORT
  ssl:
    enabled: true
    client-auth: need
    key-store: /opt/middleware/certs/server-keystore.p12
    key-store-password: changeit
    key-store-type: PKCS12
    trust-store: /opt/middleware/certs/truststore.p12
    trust-store-password: changeit
    trust-store-type: PKCS12

eureka:
  client:
    service-url:
      defaultZone: http://$EUREKA_HOST:$EUREKA_PORT/eureka/
    register-with-eureka: true
    fetch-registry: true
  instance:
    prefer-ip-address: true
    secure-port-enabled: true
    secure-port: $SERVICE_PORT
    non-secure-port-enabled: false

backend:
  url: http://$BACKEND_HOST:$BACKEND_PORT

management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: always
  server:
    port: 8092
    ssl:
      enabled: false

logging:
  level:
    com.netflix.oss: DEBUG
YAMLEOF

# Build application
echo "Building application..."
cd /tmp/netflix-oss/services/$SERVICE_NAME
mvn clean package -DskipTests -q

# Copy JAR to deployment location
echo "Deploying application..."
cp target/*.jar /opt/$SERVICE_NAME/app.jar

# =============================================================================
# Set Permissions
# =============================================================================

echo "Setting permissions..."
chown -R $SERVICE_USER:$SERVICE_USER /opt/$SERVICE_NAME
chown -R $SERVICE_USER:$SERVICE_USER /etc/$SERVICE_NAME
chown -R $SERVICE_USER:$SERVICE_USER /var/log/$SERVICE_NAME
chmod 600 /opt/$SERVICE_NAME/certs/*.key 2>/dev/null || true
chmod 600 /opt/$SERVICE_NAME/certs/*.p12 2>/dev/null || true

# =============================================================================
# Create Systemd Service
# =============================================================================

echo "Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Netflix OSS Middleware Service (mTLS)
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
Environment="EUREKA_HOST=$EUREKA_HOST"
Environment="EUREKA_PORT=$EUREKA_PORT"
Environment="BACKEND_HOST=$BACKEND_HOST"
Environment="BACKEND_PORT=$BACKEND_PORT"

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

# Wait for service to be healthy (using management port)
echo "Waiting for service to be healthy..."
for i in {1..60}; do
    if curl -s http://localhost:8092/actuator/health | grep -q "UP"; then
        echo "Service is healthy!"
        break
    fi
    echo "Waiting for service... attempt $i"
    sleep 5
done

echo "Bootstrap complete for $SERVICE_NAME at $(date)"
