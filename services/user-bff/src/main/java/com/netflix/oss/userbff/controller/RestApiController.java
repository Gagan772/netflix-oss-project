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
