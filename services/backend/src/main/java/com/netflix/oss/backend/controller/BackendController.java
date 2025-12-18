package com.netflix.oss.backend.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/backend")
public class BackendController {

    private static final Logger logger = LoggerFactory.getLogger(BackendController.class);

    @Value("${backend.version:1.0.0}")
    private String backendVersion;

    @PostMapping("/process")
    public ResponseEntity<Map<String, Object>> process(@RequestBody Map<String, Object> payload) {
        logger.info("Backend processing request: {}", payload);
        
        Map<String, Object> response = new HashMap<>();
        response.put("servedBy", "backend");
        response.put("backendVersion", backendVersion);
        response.put("processedAt", Instant.now().toString());
        response.put("requestId", UUID.randomUUID().toString());
        response.put("inputPayload", payload);
        response.put("status", "SUCCESS");
        
        // Simulate some business logic
        String operation = (String) payload.getOrDefault("operation", "unknown");
        response.put("operationProcessed", operation);
        
        if (payload.containsKey("userId")) {
            response.put("userVerified", true);
            response.put("userId", payload.get("userId"));
        }
        
        if (payload.containsKey("name")) {
            response.put("greeting", "Hello from Backend, " + payload.get("name") + "!");
        }
        
        logger.info("Backend response: {}", response);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("service", "backend");
        response.put("version", backendVersion);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/info")
    public ResponseEntity<Map<String, String>> info() {
        Map<String, String> response = new HashMap<>();
        response.put("service", "backend");
        response.put("version", backendVersion);
        response.put("description", "Netflix OSS Backend Service");
        return ResponseEntity.ok(response);
    }
}
