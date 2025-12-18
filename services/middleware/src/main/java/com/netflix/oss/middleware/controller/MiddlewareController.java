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
        
        // Extract and validate client certificate
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
        
        // Forward to backend
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

    @GetMapping("/secure-echo")
    public ResponseEntity<Map<String, Object>> secureEcho(HttpServletRequest request) {
        Map<String, Object> response = new HashMap<>();
        
        X509Certificate[] certs = (X509Certificate[]) request.getAttribute("jakarta.servlet.request.X509Certificate");
        
        if (certs != null && certs.length > 0) {
            X509Certificate clientCert = certs[0];
            response.put("mtlsVerified", true);
            response.put("clientCN", extractCN(clientCert.getSubjectX500Principal().getName()));
            response.put("issuer", clientCert.getIssuerX500Principal().getName());
            response.put("validFrom", clientCert.getNotBefore().toString());
            response.put("validTo", clientCert.getNotAfter().toString());
        } else {
            response.put("mtlsVerified", false);
            response.put("error", "No client certificate provided");
        }
        
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
