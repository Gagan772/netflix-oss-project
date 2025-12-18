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
