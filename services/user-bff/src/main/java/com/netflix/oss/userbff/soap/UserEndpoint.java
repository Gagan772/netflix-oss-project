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

    // Request class
    public static class GetUserStatusRequest {
        private String userId;

        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
    }

    // Response class
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
