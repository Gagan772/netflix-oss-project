#!/bin/bash
# =============================================================================
# User BFF Bootstrap Script (with mTLS Client)
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
MIDDLEWARE_HOST="${middleware_host}"
MIDDLEWARE_PORT="${middleware_port}"
CA_CERT='${ca_cert}'
CLIENT_CERT='${client_cert}'
CLIENT_KEY='${client_key}'

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

echo "Waiting for Middleware management port to be available..."
for i in {1..60}; do
    if curl -s http://$MIDDLEWARE_HOST:8092/actuator/health | grep -q "UP"; then
        echo "Middleware is available!"
        break
    fi
    echo "Waiting for Middleware... attempt $i"
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
# Setup PKI/Certificates for mTLS Client
# =============================================================================

echo "Setting up certificates for mTLS client..."

# Store CA certificate
cat > /opt/$SERVICE_NAME/certs/ca.crt << 'CAEOF'
$CA_CERT
CAEOF

# Store client certificate
cat > /opt/$SERVICE_NAME/certs/client.crt << 'CLTEOF'
$CLIENT_CERT
CLTEOF

# Store client key
cat > /opt/$SERVICE_NAME/certs/client.key << 'KEYEOF'
$CLIENT_KEY
KEYEOF

# Create PKCS12 keystore from client cert and key
echo "Creating client keystore..."
openssl pkcs12 -export \
    -in /opt/$SERVICE_NAME/certs/client.crt \
    -inkey /opt/$SERVICE_NAME/certs/client.key \
    -out /opt/$SERVICE_NAME/certs/client-keystore.p12 \
    -name user-bff-client \
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

mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/config
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/controller
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/service
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/soap
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/graphql
mkdir -p /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/xsd

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
    <artifactId>user-bff</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    <name>user-bff</name>

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
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web-services</artifactId>
        </dependency>
        <dependency>
            <groupId>wsdl4j</groupId>
            <artifactId>wsdl4j</artifactId>
        </dependency>
        <dependency>
            <groupId>jakarta.xml.bind</groupId>
            <artifactId>jakarta.xml.bind-api</artifactId>
        </dependency>
        <dependency>
            <groupId>org.glassfish.jaxb</groupId>
            <artifactId>jaxb-runtime</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-graphql</artifactId>
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
        <dependency>
            <groupId>org.apache.httpcomponents.client5</groupId>
            <artifactId>httpclient5</artifactId>
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
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/UserBffApplication.java << 'JAVAEOF'
package com.netflix.oss.userbff;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

@SpringBootApplication
@EnableDiscoveryClient
public class UserBffApplication {
    public static void main(String[] args) {
        SpringApplication.run(UserBffApplication.class, args);
    }
}
JAVAEOF

# Create mTLS config
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/config/MtlsConfig.java << 'JAVAEOF'
package com.netflix.oss.userbff.config;

import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.io.HttpClientConnectionManager;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactory;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactoryBuilder;
import org.apache.hc.core5.ssl.SSLContextBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import java.io.File;

@Configuration
public class MtlsConfig {

    @Value("${middleware.ssl.trust-store}")
    private String trustStorePath;

    @Value("${middleware.ssl.trust-store-password}")
    private String trustStorePassword;

    @Value("${middleware.ssl.key-store}")
    private String keyStorePath;

    @Value("${middleware.ssl.key-store-password}")
    private String keyStorePassword;

    @Value("${middleware.ssl.key-password}")
    private String keyPassword;

    @Bean
    public RestTemplate mtlsRestTemplate() throws Exception {
        File trustStoreFile = new File(trustStorePath);
        File keyStoreFile = new File(keyStorePath);

        SSLContext sslContext = SSLContextBuilder.create()
                .loadTrustMaterial(trustStoreFile, trustStorePassword.toCharArray())
                .loadKeyMaterial(keyStoreFile, keyStorePassword.toCharArray(), keyPassword.toCharArray())
                .build();

        SSLConnectionSocketFactory sslSocketFactory = SSLConnectionSocketFactoryBuilder.create()
                .setSslContext(sslContext)
                .build();

        HttpClientConnectionManager connectionManager = PoolingHttpClientConnectionManagerBuilder.create()
                .setSSLSocketFactory(sslSocketFactory)
                .build();

        CloseableHttpClient httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .build();

        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout(10000);

        return new RestTemplate(factory);
    }
}
JAVAEOF

# Create WebService config
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/config/WebServiceConfig.java << 'JAVAEOF'
package com.netflix.oss.userbff.config;

import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.ws.config.annotation.EnableWs;
import org.springframework.ws.config.annotation.WsConfigurerAdapter;
import org.springframework.ws.transport.http.MessageDispatcherServlet;
import org.springframework.ws.wsdl.wsdl11.DefaultWsdl11Definition;
import org.springframework.xml.xsd.SimpleXsdSchema;
import org.springframework.xml.xsd.XsdSchema;

@EnableWs
@Configuration
public class WebServiceConfig extends WsConfigurerAdapter {

    @Bean
    public ServletRegistrationBean<MessageDispatcherServlet> messageDispatcherServlet(ApplicationContext applicationContext) {
        MessageDispatcherServlet servlet = new MessageDispatcherServlet();
        servlet.setApplicationContext(applicationContext);
        servlet.setTransformWsdlLocations(true);
        return new ServletRegistrationBean<>(servlet, "/ws/*");
    }

    @Bean(name = "users")
    public DefaultWsdl11Definition defaultWsdl11Definition(XsdSchema usersSchema) {
        DefaultWsdl11Definition wsdl11Definition = new DefaultWsdl11Definition();
        wsdl11Definition.setPortTypeName("UsersPort");
        wsdl11Definition.setLocationUri("/ws");
        wsdl11Definition.setTargetNamespace("http://netflix.oss/user");
        wsdl11Definition.setSchema(usersSchema);
        return wsdl11Definition;
    }

    @Bean
    public XsdSchema usersSchema() {
        return new SimpleXsdSchema(new ClassPathResource("xsd/users.xsd"));
    }
}
JAVAEOF

# Create MiddlewareService
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/service/MiddlewareService.java << 'JAVAEOF'
package com.netflix.oss.userbff.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
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
public class MiddlewareService {

    private static final Logger logger = LoggerFactory.getLogger(MiddlewareService.class);

    private final RestTemplate mtlsRestTemplate;
    private final String middlewareUrl;

    public MiddlewareService(
            @Qualifier("mtlsRestTemplate") RestTemplate mtlsRestTemplate,
            @Value("${middleware.url}") String middlewareUrl) {
        this.mtlsRestTemplate = mtlsRestTemplate;
        this.middlewareUrl = middlewareUrl;
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> callMiddleware(Map<String, Object> payload) {
        logger.info("Calling middleware with mTLS at: {}", middlewareUrl);
        
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(payload, headers);
            
            ResponseEntity<Map> response = mtlsRestTemplate.postForEntity(
                    middlewareUrl + "/api/mw/forward",
                    request,
                    Map.class
            );
            
            logger.info("Middleware response status: {}", response.getStatusCode());
            return response.getBody();
        } catch (Exception e) {
            logger.error("Error calling middleware: {}", e.getMessage(), e);
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            errorResponse.put("mtlsVerified", false);
            errorResponse.put("servedBy", "error");
            return errorResponse;
        }
    }
}
JAVAEOF

# Create REST controller
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/controller/RestApiController.java << 'JAVAEOF'
package com.netflix.oss.userbff.controller;

import com.netflix.oss.userbff.service.MiddlewareService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/rest")
public class RestApiController {

    private static final Logger logger = LoggerFactory.getLogger(RestApiController.class);

    private final MiddlewareService middlewareService;

    public RestApiController(MiddlewareService middlewareService) {
        this.middlewareService = middlewareService;
    }

    @GetMapping("/hello")
    public ResponseEntity<Map<String, Object>> hello(@RequestParam(defaultValue = "World") String name) {
        logger.info("REST endpoint called with name: {}", name);
        
        Map<String, Object> payload = new HashMap<>();
        payload.put("name", name);
        payload.put("operation", "hello");
        payload.put("source", "rest-api");
        
        Map<String, Object> response = middlewareService.callMiddleware(payload);
        response.put("greeting", "Hello, " + name + "!");
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "user-bff");
        return ResponseEntity.ok(response);
    }
}
JAVAEOF

# Create GraphQL controller
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/controller/GraphQLController.java << 'JAVAEOF'
package com.netflix.oss.userbff.controller;

import com.netflix.oss.userbff.service.MiddlewareService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

import java.util.HashMap;
import java.util.Map;

@Controller
public class GraphQLController {

    private static final Logger logger = LoggerFactory.getLogger(GraphQLController.class);

    private final MiddlewareService middlewareService;

    public GraphQLController(MiddlewareService middlewareService) {
        this.middlewareService = middlewareService;
    }

    @QueryMapping
    public UserStatus userStatus(@Argument String id) {
        logger.info("GraphQL query for user status with id: {}", id);
        
        Map<String, Object> payload = new HashMap<>();
        payload.put("userId", id);
        payload.put("operation", "getUserStatus");
        payload.put("source", "graphql-api");
        
        Map<String, Object> response = middlewareService.callMiddleware(payload);
        
        UserStatus userStatus = new UserStatus();
        userStatus.setId(id);
        userStatus.setStatus("ACTIVE");
        userStatus.setServedBy((String) response.getOrDefault("servedBy", "unknown"));
        userStatus.setMtlsVerified((Boolean) response.getOrDefault("mtlsVerified", false));
        userStatus.setClientCN((String) response.getOrDefault("clientCN", "unknown"));
        userStatus.setBackendVersion((String) response.getOrDefault("backendVersion", "unknown"));
        
        return userStatus;
    }

    public static class UserStatus {
        private String id;
        private String status;
        private String servedBy;
        private Boolean mtlsVerified;
        private String clientCN;
        private String backendVersion;

        public String getId() { return id; }
        public void setId(String id) { this.id = id; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public String getServedBy() { return servedBy; }
        public void setServedBy(String servedBy) { this.servedBy = servedBy; }
        public Boolean getMtlsVerified() { return mtlsVerified; }
        public void setMtlsVerified(Boolean mtlsVerified) { this.mtlsVerified = mtlsVerified; }
        public String getClientCN() { return clientCN; }
        public void setClientCN(String clientCN) { this.clientCN = clientCN; }
        public String getBackendVersion() { return backendVersion; }
        public void setBackendVersion(String backendVersion) { this.backendVersion = backendVersion; }
    }
}
JAVAEOF

# Create SOAP endpoint
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/java/com/netflix/oss/userbff/soap/UserEndpoint.java << 'JAVAEOF'
package com.netflix.oss.userbff.soap;

import com.netflix.oss.userbff.service.MiddlewareService;
import jakarta.xml.bind.JAXBElement;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ws.server.endpoint.annotation.Endpoint;
import org.springframework.ws.server.endpoint.annotation.PayloadRoot;
import org.springframework.ws.server.endpoint.annotation.RequestPayload;
import org.springframework.ws.server.endpoint.annotation.ResponsePayload;

import javax.xml.namespace.QName;
import java.util.HashMap;
import java.util.Map;

@Endpoint
public class UserEndpoint {

    private static final Logger logger = LoggerFactory.getLogger(UserEndpoint.class);
    private static final String NAMESPACE_URI = "http://netflix.oss/user";

    private final MiddlewareService middlewareService;

    public UserEndpoint(MiddlewareService middlewareService) {
        this.middlewareService = middlewareService;
    }

    @PayloadRoot(namespace = NAMESPACE_URI, localPart = "GetUserStatusRequest")
    @ResponsePayload
    public JAXBElement<GetUserStatusResponse> getUserStatus(@RequestPayload JAXBElement<GetUserStatusRequest> request) {
        GetUserStatusRequest req = request.getValue();
        logger.info("SOAP request for user status with userId: {}", req.getUserId());
        
        Map<String, Object> payload = new HashMap<>();
        payload.put("userId", req.getUserId());
        payload.put("operation", "getUserStatus");
        payload.put("source", "soap-api");
        
        Map<String, Object> middlewareResponse = middlewareService.callMiddleware(payload);
        
        GetUserStatusResponse response = new GetUserStatusResponse();
        response.setUserId(req.getUserId());
        response.setStatus("ACTIVE");
        response.setServedBy((String) middlewareResponse.getOrDefault("servedBy", "unknown"));
        response.setMtlsVerified((Boolean) middlewareResponse.getOrDefault("mtlsVerified", false));
        response.setClientCN((String) middlewareResponse.getOrDefault("clientCN", "unknown"));
        response.setBackendVersion((String) middlewareResponse.getOrDefault("backendVersion", "unknown"));
        
        return new JAXBElement<>(
                new QName(NAMESPACE_URI, "GetUserStatusResponse"),
                GetUserStatusResponse.class,
                response
        );
    }

    public static class GetUserStatusRequest {
        private String userId;
        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
    }

    public static class GetUserStatusResponse {
        private String userId;
        private String status;
        private String servedBy;
        private Boolean mtlsVerified;
        private String clientCN;
        private String backendVersion;

        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
        public String getStatus() { return status; }
        public void setStatus(String status) { this.status = status; }
        public String getServedBy() { return servedBy; }
        public void setServedBy(String servedBy) { this.servedBy = servedBy; }
        public Boolean getMtlsVerified() { return mtlsVerified; }
        public void setMtlsVerified(Boolean mtlsVerified) { this.mtlsVerified = mtlsVerified; }
        public String getClientCN() { return clientCN; }
        public void setClientCN(String clientCN) { this.clientCN = clientCN; }
        public String getBackendVersion() { return backendVersion; }
        public void setBackendVersion(String backendVersion) { this.backendVersion = backendVersion; }
    }
}
JAVAEOF

# Create GraphQL schema
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/graphql/schema.graphqls << 'GQLEOF'
type Query {
    userStatus(id: String!): UserStatus
}

type UserStatus {
    id: String!
    status: String!
    servedBy: String
    mtlsVerified: Boolean
    clientCN: String
    backendVersion: String
}
GQLEOF

# Create XSD for SOAP
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/xsd/users.xsd << 'XSDEOF'
<?xml version="1.0" encoding="UTF-8"?>
<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
           xmlns:tns="http://netflix.oss/user"
           targetNamespace="http://netflix.oss/user"
           elementFormDefault="qualified">

    <xs:element name="GetUserStatusRequest">
        <xs:complexType>
            <xs:sequence>
                <xs:element name="userId" type="xs:string"/>
            </xs:sequence>
        </xs:complexType>
    </xs:element>

    <xs:element name="GetUserStatusResponse">
        <xs:complexType>
            <xs:sequence>
                <xs:element name="userId" type="xs:string"/>
                <xs:element name="status" type="xs:string"/>
                <xs:element name="servedBy" type="xs:string"/>
                <xs:element name="mtlsVerified" type="xs:boolean"/>
                <xs:element name="clientCN" type="xs:string"/>
                <xs:element name="backendVersion" type="xs:string"/>
            </xs:sequence>
        </xs:complexType>
    </xs:element>
</xs:schema>
XSDEOF

# Create application.yml
cat > /tmp/netflix-oss/services/$SERVICE_NAME/src/main/resources/application.yml << YAMLEOF
spring:
  application:
    name: user-bff
  config:
    import: optional:configserver:http://$CONFIG_HOST:$CONFIG_PORT
  graphql:
    graphiql:
      enabled: true
    path: /graphql
    schema:
      locations: classpath:graphql/

server:
  port: $SERVICE_PORT

eureka:
  client:
    service-url:
      defaultZone: http://$EUREKA_HOST:$EUREKA_PORT/eureka/
    register-with-eureka: true
    fetch-registry: true
  instance:
    prefer-ip-address: true

middleware:
  url: https://$MIDDLEWARE_HOST:$MIDDLEWARE_PORT
  ssl:
    trust-store: /opt/user-bff/certs/truststore.p12
    trust-store-password: changeit
    key-store: /opt/user-bff/certs/client-keystore.p12
    key-store-password: changeit
    key-password: changeit

management:
  endpoints:
    web:
      exposure:
        include: health,info
  endpoint:
    health:
      show-details: always

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
Description=Netflix OSS User BFF Service
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
Environment="MIDDLEWARE_HOST=$MIDDLEWARE_HOST"
Environment="MIDDLEWARE_PORT=$MIDDLEWARE_PORT"

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
