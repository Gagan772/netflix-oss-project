# =============================================================================
# Netflix OSS Microservices Stack - Security Groups
# =============================================================================

# Bastion/SSH Security Group
resource "aws_security_group" "ssh" {
  name        = "${var.project_name}-ssh-sg"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ssh-sg"
  }
}

# Config Server Security Group
resource "aws_security_group" "config_server" {
  name        = "${var.project_name}-config-server-sg"
  description = "Security group for Config Server"
  vpc_id      = aws_vpc.main.id

  # Allow config access from all services in VPC
  ingress {
    description = "Config Server port from VPC"
    from_port   = var.config_server_port
    to_port     = var.config_server_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-config-server-sg"
  }
}

# Eureka Server Security Group
resource "aws_security_group" "eureka_server" {
  name        = "${var.project_name}-eureka-server-sg"
  description = "Security group for Eureka Server"
  vpc_id      = aws_vpc.main.id

  # Allow Eureka access from all services in VPC
  ingress {
    description = "Eureka Server port from VPC"
    from_port   = var.eureka_server_port
    to_port     = var.eureka_server_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow Eureka dashboard access from internet
  ingress {
    description = "Eureka Dashboard from internet"
    from_port   = var.eureka_server_port
    to_port     = var.eureka_server_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eureka-server-sg"
  }
}

# Cloud Gateway Security Group
resource "aws_security_group" "cloud_gateway" {
  name        = "${var.project_name}-cloud-gateway-sg"
  description = "Security group for Cloud Gateway"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP access from anywhere (entry point)
  ingress {
    description = "Gateway HTTP port from allowed CIDR"
    from_port   = var.gateway_port
    to_port     = var.gateway_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-cloud-gateway-sg"
  }
}

# User BFF Security Group
resource "aws_security_group" "user_bff" {
  name        = "${var.project_name}-user-bff-sg"
  description = "Security group for User BFF"
  vpc_id      = aws_vpc.main.id

  # Allow access only from Cloud Gateway
  ingress {
    description     = "User BFF port from Cloud Gateway"
    from_port       = var.user_bff_port
    to_port         = var.user_bff_port
    protocol        = "tcp"
    security_groups = [aws_security_group.cloud_gateway.id]
  }

  # Also allow from VPC for health checks
  ingress {
    description = "User BFF port from VPC"
    from_port   = var.user_bff_port
    to_port     = var.user_bff_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-user-bff-sg"
  }
}

# Middleware Security Group
resource "aws_security_group" "middleware" {
  name        = "${var.project_name}-middleware-sg"
  description = "Security group for Middleware (mTLS)"
  vpc_id      = aws_vpc.main.id

  # Allow access only from User BFF
  ingress {
    description     = "Middleware mTLS port from User BFF"
    from_port       = var.middleware_port
    to_port         = var.middleware_port
    protocol        = "tcp"
    security_groups = [aws_security_group.user_bff.id]
  }

  # Also allow from VPC for health checks
  ingress {
    description = "Middleware port from VPC"
    from_port   = var.middleware_port
    to_port     = var.middleware_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-middleware-sg"
  }
}

# Backend Security Group
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Security group for Backend"
  vpc_id      = aws_vpc.main.id

  # Allow access only from Middleware
  ingress {
    description     = "Backend port from Middleware"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.middleware.id]
  }

  # Also allow from VPC for health checks
  ingress {
    description = "Backend port from VPC"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}
