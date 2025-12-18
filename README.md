# Netflix OSS Microservices Stack on AWS

A complete, production-ready Netflix OSS microservices architecture deployed on AWS EC2 using Terraform with **zero manual steps**.

## Architecture Overview

```
                                    ┌─────────────────┐
                                    │  Config Server  │
                                    │    (8888)       │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │  Eureka Server  │
                                    │    (8761)       │
                                    └────────┬────────┘
                                             │
┌──────────┐    ┌─────────────┐    ┌────────▼────────┐    ┌────────────┐    ┌─────────┐
│  Client  │───▶│Cloud Gateway│───▶│    User BFF     │───▶│ Middleware │───▶│ Backend │
│          │    │   (8080)    │    │    (8081)       │    │   (8082)   │    │ (8083)  │
└──────────┘    └─────────────┘    │ REST/SOAP/GQL   │    │   mTLS     │    └─────────┘
                                   └─────────────────┘    └────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| config-server | 8888 | Spring Cloud Config Server |
| eureka-server | 8761 | Netflix Eureka Service Discovery |
| cloud-gateway | 8080 | Spring Cloud Gateway (Entry Point) |
| user-bff | 8081 | Backend for Frontend (REST, SOAP, GraphQL) |
| middleware | 8082 | mTLS enforcement, certificate validation |
| backend | 8083 | Business logic service |

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- SSH key pair (will be created automatically or you can provide your own)
- Bash shell (for sanity scripts on Windows, use Git Bash or WSL)

## Quick Start

### 1. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region (e.g., us-east-1)
```

### 2. Deploy the Stack

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

This single command will:
- Create VPC, subnets, internet gateway, and route tables
- Create security groups with proper access rules
- Launch 6 EC2 instances (t3.medium, Ubuntu 22.04)
- Install Java 17, Maven, and Git on each instance
- Clone and build all Spring Boot applications
- Generate PKI (Root CA, server certs, client certs) for mTLS
- Configure and start all services with systemd
- Run sanity checks and generate a report

### 3. Access the Services

After deployment, Terraform will output:
- Gateway URL (public entry point)
- Service URLs
- Sanity report location

### 4. Test the APIs

#### REST Endpoint
```bash
curl "http://<GATEWAY_IP>:8080/api/rest/hello?name=World"
```

#### SOAP Endpoint
```bash
curl -X POST "http://<GATEWAY_IP>:8080/ws" \
  -H "Content-Type: text/xml" \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                  xmlns:user="http://netflix.oss/user">
   <soapenv:Header/>
   <soapenv:Body>
      <user:GetUserStatusRequest>
         <user:userId>123</user:userId>
      </user:GetUserStatusRequest>
   </soapenv:Body>
</soapenv:Envelope>'
```

#### GraphQL Endpoint
```bash
curl -X POST "http://<GATEWAY_IP>:8080/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { userStatus(id: \"1\") { status servedBy mtlsVerified clientCN } }"}'
```

### 5. Destroy the Stack

```bash
terraform destroy -auto-approve
```

## mTLS Configuration

The stack implements mutual TLS (mTLS) between user-bff and middleware:

- **Root CA**: Self-signed CA certificate generated during provisioning
- **Server Certificate**: Used by middleware for TLS server authentication
- **Client Certificate**: Used by user-bff to authenticate to middleware
- **Truststore**: Contains Root CA for certificate chain validation

The middleware validates:
1. Client certificate is present
2. Certificate chain is valid (signed by trusted CA)
3. Certificate is not expired

## Sanity Report

After successful deployment, a sanity report is generated at:
- `./sanity-report.json` - Machine-readable JSON format
- `./sanity-report.txt` - Human-readable text format

The report includes:
- Timestamp of tests
- Each endpoint tested (REST, SOAP, GraphQL)
- HTTP status codes
- Response validation (servedBy=backend, mtlsVerified=true)
- Overall pass/fail status

## Project Structure

```
netflix-oss-project/
├── terraform/
│   ├── main.tf              # Main Terraform configuration
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   ├── network.tf           # VPC, subnets, IGW, routes
│   ├── security.tf          # Security groups
│   ├── instances.tf         # EC2 instances
│   ├── iam.tf               # IAM roles and policies
│   ├── provisioning/        # Bootstrap scripts
│   │   ├── common.sh        # Common setup script
│   │   ├── config-server.sh
│   │   ├── eureka-server.sh
│   │   ├── cloud-gateway.sh
│   │   ├── user-bff.sh
│   │   ├── middleware.sh
│   │   ├── backend.sh
│   │   └── pki-setup.sh     # Certificate generation
│   └── sanity/
│       └── sanity-check.sh  # Sanity test script
├── services/
│   ├── config-server/
│   ├── eureka-server/
│   ├── cloud-gateway/
│   ├── user-bff/
│   ├── middleware/
│   └── backend/
├── config-repo/             # Configuration files for Config Server
│   ├── application.yml
│   ├── eureka-server.yml
│   ├── cloud-gateway.yml
│   ├── user-bff.yml
│   ├── middleware.yml
│   └── backend.yml
└── README.md
```

## Troubleshooting

### Check Service Status
```bash
# SSH to any instance and check systemd status
ssh -i <key> ubuntu@<instance-ip>
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -f
```

### Common Issues

1. **Services not starting**: Check if config-server and eureka-server are healthy first
2. **mTLS failures**: Verify certificates are properly generated in /opt/<service>/certs
3. **Timeout during apply**: Increase timeout values in Terraform or check AWS quotas

## Security Considerations

- All inter-service communication (except to gateway) is restricted to VPC
- mTLS enforced between user-bff and middleware
- Security groups implement least-privilege access
- Private keys are protected with file permissions (600)
- Services run as dedicated Linux users

## License

MIT License
