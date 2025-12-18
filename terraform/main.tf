# =============================================================================
# Netflix OSS Microservices Stack - Main Terraform Configuration
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# SSH Key Pair
# =============================================================================

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${var.key_name}-${random_id.suffix.hex}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/netflix-oss-key.pem"
  file_permission = "0600"
}

# =============================================================================
# PKI Generation for mTLS
# =============================================================================

# Root CA Private Key
resource "tls_private_key" "root_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Root CA Certificate
resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name         = "Netflix OSS Root CA"
    organization        = "Netflix OSS Demo"
    organizational_unit = "DevOps"
    country             = "US"
    province            = "California"
    locality            = "San Jose"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# Middleware Server Private Key
resource "tls_private_key" "middleware_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Middleware Server Certificate Request
resource "tls_cert_request" "middleware_server" {
  private_key_pem = tls_private_key.middleware_server.private_key_pem

  subject {
    common_name         = "middleware"
    organization        = "Netflix OSS Demo"
    organizational_unit = "Services"
  }

  dns_names = [
    "middleware",
    "localhost",
    "middleware.${var.project_name}.internal"
  ]

  ip_addresses = ["127.0.0.1"]
}

# Middleware Server Certificate (signed by Root CA)
resource "tls_locally_signed_cert" "middleware_server" {
  cert_request_pem   = tls_cert_request.middleware_server.cert_request_pem
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# User BFF Client Private Key
resource "tls_private_key" "userbff_client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# User BFF Client Certificate Request
resource "tls_cert_request" "userbff_client" {
  private_key_pem = tls_private_key.userbff_client.private_key_pem

  subject {
    common_name         = "user-bff-client"
    organization        = "Netflix OSS Demo"
    organizational_unit = "Services"
  }
}

# User BFF Client Certificate (signed by Root CA)
resource "tls_locally_signed_cert" "userbff_client" {
  cert_request_pem   = tls_cert_request.userbff_client.cert_request_pem
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

# Save certificates to local files for provisioning
resource "local_file" "root_ca_cert" {
  content  = tls_self_signed_cert.root_ca.cert_pem
  filename = "${path.module}/certs/ca.crt"
}

resource "local_file" "root_ca_key" {
  content         = tls_private_key.root_ca.private_key_pem
  filename        = "${path.module}/certs/ca.key"
  file_permission = "0600"
}

resource "local_file" "middleware_server_cert" {
  content  = tls_locally_signed_cert.middleware_server.cert_pem
  filename = "${path.module}/certs/middleware-server.crt"
}

resource "local_file" "middleware_server_key" {
  content         = tls_private_key.middleware_server.private_key_pem
  filename        = "${path.module}/certs/middleware-server.key"
  file_permission = "0600"
}

resource "local_file" "userbff_client_cert" {
  content  = tls_locally_signed_cert.userbff_client.cert_pem
  filename = "${path.module}/certs/userbff-client.crt"
}

resource "local_file" "userbff_client_key" {
  content         = tls_private_key.userbff_client.private_key_pem
  filename        = "${path.module}/certs/userbff-client.key"
  file_permission = "0600"
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  services = {
    config-server = {
      port        = var.config_server_port
      user        = "svc_config"
      description = "Spring Cloud Config Server"
    }
    eureka-server = {
      port        = var.eureka_server_port
      user        = "svc_eureka"
      description = "Netflix Eureka Service Discovery"
    }
    cloud-gateway = {
      port        = var.gateway_port
      user        = "svc_gateway"
      description = "Spring Cloud Gateway"
    }
    user-bff = {
      port        = var.user_bff_port
      user        = "svc_userbff"
      description = "User BFF Service"
    }
    middleware = {
      port        = var.middleware_port
      user        = "svc_middleware"
      description = "Middleware Service with mTLS"
    }
    backend = {
      port        = var.backend_port
      user        = "svc_backend"
      description = "Backend Service"
    }
  }

  # Certificate content for embedding in scripts
  ca_cert_content              = tls_self_signed_cert.root_ca.cert_pem
  middleware_server_cert       = tls_locally_signed_cert.middleware_server.cert_pem
  middleware_server_key        = tls_private_key.middleware_server.private_key_pem
  userbff_client_cert          = tls_locally_signed_cert.userbff_client.cert_pem
  userbff_client_key           = tls_private_key.userbff_client.private_key_pem
}
