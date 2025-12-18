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
