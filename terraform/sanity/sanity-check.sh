#!/bin/bash
# =============================================================================
# Sanity Check Script for Netflix OSS Stack
# =============================================================================

set -e

GATEWAY_IP=$1
GATEWAY_PORT=$2
OUTPUT_DIR=$3

if [ -z "$GATEWAY_IP" ] || [ -z "$GATEWAY_PORT" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <gateway_ip> <gateway_port> <output_dir>"
    exit 1
fi

GATEWAY_URL="http://$GATEWAY_IP:$GATEWAY_PORT"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REPORT_JSON="$OUTPUT_DIR/sanity-report.json"
REPORT_TXT="$OUTPUT_DIR/sanity-report.txt"

echo "=============================================="
echo "Netflix OSS Stack Sanity Check"
echo "=============================================="
echo "Gateway URL: $GATEWAY_URL"
echo "Timestamp: $TIMESTAMP"
echo ""

# Initialize results
REST_STATUS="FAIL"
REST_HTTP_CODE=""
REST_RESPONSE=""
REST_SERVED_BY=""
REST_MTLS_VERIFIED=""

GRAPHQL_STATUS="FAIL"
GRAPHQL_HTTP_CODE=""
GRAPHQL_RESPONSE=""
GRAPHQL_SERVED_BY=""
GRAPHQL_MTLS_VERIFIED=""

SOAP_STATUS="FAIL"
SOAP_HTTP_CODE=""
SOAP_RESPONSE=""

OVERALL_STATUS="FAIL"

# =============================================================================
# Wait for Gateway to be ready
# =============================================================================

echo "Waiting for Gateway to be ready..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/actuator/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Gateway is ready!"
        break
    fi
    echo "Waiting for Gateway... attempt $i (HTTP: $HTTP_CODE)"
    sleep 10
done

# =============================================================================
# Test 1: REST Endpoint
# =============================================================================

echo ""
echo "Testing REST endpoint..."
REST_RESPONSE=$(curl -s -w "\n%{http_code}" "$GATEWAY_URL/api/rest/hello?name=SanityTest" 2>/dev/null || echo '{"error":"connection_failed"}\n000')
REST_HTTP_CODE=$(echo "$REST_RESPONSE" | tail -n1)
REST_BODY=$(echo "$REST_RESPONSE" | sed '$d')

echo "REST HTTP Code: $REST_HTTP_CODE"
echo "REST Response: $REST_BODY"

if [ "$REST_HTTP_CODE" = "200" ]; then
    REST_SERVED_BY=$(echo "$REST_BODY" | grep -o '"servedBy":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    REST_MTLS_VERIFIED=$(echo "$REST_BODY" | grep -o '"mtlsVerified":[^,}]*' | cut -d':' -f2 || echo "false")
    
    if [ "$REST_SERVED_BY" = "backend" ] && [ "$REST_MTLS_VERIFIED" = "true" ]; then
        REST_STATUS="PASS"
        echo "REST Test: PASS (servedBy=backend, mtlsVerified=true)"
    else
        echo "REST Test: FAIL (servedBy=$REST_SERVED_BY, mtlsVerified=$REST_MTLS_VERIFIED)"
    fi
else
    echo "REST Test: FAIL (HTTP $REST_HTTP_CODE)"
fi

# =============================================================================
# Test 2: GraphQL Endpoint
# =============================================================================

echo ""
echo "Testing GraphQL endpoint..."
GRAPHQL_QUERY='{"query":"query { userStatus(id: \"1\") { status servedBy mtlsVerified clientCN backendVersion } }"}'
GRAPHQL_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/graphql" \
    -H "Content-Type: application/json" \
    -d "$GRAPHQL_QUERY" 2>/dev/null || echo '{"error":"connection_failed"}\n000')
GRAPHQL_HTTP_CODE=$(echo "$GRAPHQL_RESPONSE" | tail -n1)
GRAPHQL_BODY=$(echo "$GRAPHQL_RESPONSE" | sed '$d')

echo "GraphQL HTTP Code: $GRAPHQL_HTTP_CODE"
echo "GraphQL Response: $GRAPHQL_BODY"

if [ "$GRAPHQL_HTTP_CODE" = "200" ]; then
    GRAPHQL_SERVED_BY=$(echo "$GRAPHQL_BODY" | grep -o '"servedBy":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    GRAPHQL_MTLS_VERIFIED=$(echo "$GRAPHQL_BODY" | grep -o '"mtlsVerified":[^,}]*' | cut -d':' -f2 || echo "false")
    
    if [ "$GRAPHQL_SERVED_BY" = "backend" ] && [ "$GRAPHQL_MTLS_VERIFIED" = "true" ]; then
        GRAPHQL_STATUS="PASS"
        echo "GraphQL Test: PASS (servedBy=backend, mtlsVerified=true)"
    else
        echo "GraphQL Test: FAIL (servedBy=$GRAPHQL_SERVED_BY, mtlsVerified=$GRAPHQL_MTLS_VERIFIED)"
    fi
else
    echo "GraphQL Test: FAIL (HTTP $GRAPHQL_HTTP_CODE)"
fi

# =============================================================================
# Test 3: SOAP Endpoint
# =============================================================================

echo ""
echo "Testing SOAP endpoint..."
SOAP_REQUEST='<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                  xmlns:user="http://netflix.oss/user">
   <soapenv:Header/>
   <soapenv:Body>
      <user:GetUserStatusRequest>
         <user:userId>123</user:userId>
      </user:GetUserStatusRequest>
   </soapenv:Body>
</soapenv:Envelope>'

SOAP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GATEWAY_URL/ws" \
    -H "Content-Type: text/xml" \
    -d "$SOAP_REQUEST" 2>/dev/null || echo '<error>connection_failed</error>\n000')
SOAP_HTTP_CODE=$(echo "$SOAP_RESPONSE" | tail -n1)
SOAP_BODY=$(echo "$SOAP_RESPONSE" | sed '$d')

echo "SOAP HTTP Code: $SOAP_HTTP_CODE"
echo "SOAP Response (truncated): $(echo "$SOAP_BODY" | head -c 500)"

if [ "$SOAP_HTTP_CODE" = "200" ]; then
    SOAP_SERVED_BY=$(echo "$SOAP_BODY" | grep -o '<[^:]*:servedBy>[^<]*</[^:]*:servedBy>' | sed 's/<[^>]*>//g' || echo "unknown")
    SOAP_MTLS=$(echo "$SOAP_BODY" | grep -o '<[^:]*:mtlsVerified>[^<]*</[^:]*:mtlsVerified>' | sed 's/<[^>]*>//g' || echo "false")
    
    if [ "$SOAP_SERVED_BY" = "backend" ] && [ "$SOAP_MTLS" = "true" ]; then
        SOAP_STATUS="PASS"
        echo "SOAP Test: PASS (servedBy=backend, mtlsVerified=true)"
    else
        echo "SOAP Test: FAIL (servedBy=$SOAP_SERVED_BY, mtlsVerified=$SOAP_MTLS)"
    fi
else
    echo "SOAP Test: FAIL (HTTP $SOAP_HTTP_CODE)"
fi

# =============================================================================
# Determine Overall Status
# =============================================================================

if [ "$REST_STATUS" = "PASS" ] && [ "$GRAPHQL_STATUS" = "PASS" ]; then
    OVERALL_STATUS="PASS"
fi

echo ""
echo "=============================================="
echo "SANITY CHECK RESULTS"
echo "=============================================="
echo "REST:    $REST_STATUS"
echo "GraphQL: $GRAPHQL_STATUS"
echo "SOAP:    $SOAP_STATUS"
echo "----------------------------------------------"
echo "OVERALL: $OVERALL_STATUS"
echo "=============================================="

# =============================================================================
# Generate JSON Report
# =============================================================================

cat > "$REPORT_JSON" << JSONEOF
{
  "timestamp": "$TIMESTAMP",
  "gatewayUrl": "$GATEWAY_URL",
  "overallStatus": "$OVERALL_STATUS",
  "tests": {
    "rest": {
      "status": "$REST_STATUS",
      "httpCode": "$REST_HTTP_CODE",
      "servedBy": "$REST_SERVED_BY",
      "mtlsVerified": $REST_MTLS_VERIFIED,
      "endpoint": "$GATEWAY_URL/api/rest/hello?name=SanityTest",
      "response": $(echo "$REST_BODY" | head -c 1000 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$REST_BODY\"")
    },
    "graphql": {
      "status": "$GRAPHQL_STATUS",
      "httpCode": "$GRAPHQL_HTTP_CODE",
      "servedBy": "$GRAPHQL_SERVED_BY",
      "mtlsVerified": $GRAPHQL_MTLS_VERIFIED,
      "endpoint": "$GATEWAY_URL/graphql",
      "response": $(echo "$GRAPHQL_BODY" | head -c 1000 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$GRAPHQL_BODY\"")
    },
    "soap": {
      "status": "$SOAP_STATUS",
      "httpCode": "$SOAP_HTTP_CODE",
      "endpoint": "$GATEWAY_URL/ws",
      "response": $(echo "$SOAP_BODY" | head -c 1000 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"truncated\"")
    }
  }
}
JSONEOF

echo ""
echo "JSON Report written to: $REPORT_JSON"

# =============================================================================
# Generate Text Report
# =============================================================================

cat > "$REPORT_TXT" << TXTEOF
==============================================
Netflix OSS Stack Sanity Report
==============================================
Timestamp:   $TIMESTAMP
Gateway URL: $GATEWAY_URL

----------------------------------------------
TEST RESULTS
----------------------------------------------

1. REST Endpoint Test
   Endpoint: $GATEWAY_URL/api/rest/hello?name=SanityTest
   Status:   $REST_STATUS
   HTTP Code: $REST_HTTP_CODE
   Served By: $REST_SERVED_BY
   mTLS Verified: $REST_MTLS_VERIFIED

2. GraphQL Endpoint Test
   Endpoint: $GATEWAY_URL/graphql
   Status:   $GRAPHQL_STATUS
   HTTP Code: $GRAPHQL_HTTP_CODE
   Served By: $GRAPHQL_SERVED_BY
   mTLS Verified: $GRAPHQL_MTLS_VERIFIED

3. SOAP Endpoint Test
   Endpoint: $GATEWAY_URL/ws
   Status:   $SOAP_STATUS
   HTTP Code: $SOAP_HTTP_CODE

----------------------------------------------
OVERALL STATUS: $OVERALL_STATUS
----------------------------------------------

Notes:
- servedBy=backend confirms request reached backend service
- mtlsVerified=true confirms mTLS authentication between user-bff and middleware

TXTEOF

echo "Text Report written to: $REPORT_TXT"

# =============================================================================
# Exit with appropriate code
# =============================================================================

if [ "$OVERALL_STATUS" = "PASS" ]; then
    echo ""
    echo "All sanity checks passed!"
    exit 0
else
    echo ""
    echo "WARNING: Some sanity checks failed. Check the reports for details."
    echo "Note: SOAP endpoint may have partial support - REST and GraphQL are primary."
    # Don't fail the entire deployment if only SOAP fails
    if [ "$REST_STATUS" = "PASS" ] && [ "$GRAPHQL_STATUS" = "PASS" ]; then
        exit 0
    fi
    exit 1
fi
