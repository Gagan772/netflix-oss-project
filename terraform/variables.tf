# =============================================================================
# Netflix OSS Microservices Stack - Terraform Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "netflix-oss"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair to create"
  type        = string
  default     = "netflix-oss-key"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_http_cidr" {
  description = "CIDR block allowed for HTTP access to gateway"
  type        = string
  default     = "0.0.0.0/0"
}

# Service ports
variable "config_server_port" {
  description = "Port for Config Server"
  type        = number
  default     = 8888
}

variable "eureka_server_port" {
  description = "Port for Eureka Server"
  type        = number
  default     = 8761
}

variable "gateway_port" {
  description = "Port for Cloud Gateway"
  type        = number
  default     = 8080
}

variable "user_bff_port" {
  description = "Port for User BFF"
  type        = number
  default     = 8081
}

variable "middleware_port" {
  description = "Port for Middleware (mTLS)"
  type        = number
  default     = 8082
}

variable "backend_port" {
  description = "Port for Backend"
  type        = number
  default     = 8083
}

# GitHub repository URL for the project (used by instances to clone code)
variable "github_repo_url" {
  description = "GitHub repository URL containing the Spring Boot services"
  type        = string
  default     = ""  # Will be set dynamically or use local files
}

# Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Netflix-OSS"
    Environment = "Demo"
    ManagedBy   = "Terraform"
  }
}
