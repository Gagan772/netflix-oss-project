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
