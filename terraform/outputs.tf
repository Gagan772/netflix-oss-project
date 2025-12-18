# =============================================================================
# Netflix OSS Microservices Stack - Outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

# =============================================================================
# Instance IPs
# =============================================================================

output "config_server_public_ip" {
  description = "Public IP of Config Server"
  value       = aws_instance.config_server.public_ip
}

output "config_server_private_ip" {
  description = "Private IP of Config Server"
  value       = aws_instance.config_server.private_ip
}

output "eureka_server_public_ip" {
  description = "Public IP of Eureka Server"
  value       = aws_instance.eureka_server.public_ip
}

output "eureka_server_private_ip" {
  description = "Private IP of Eureka Server"
  value       = aws_instance.eureka_server.private_ip
}

output "cloud_gateway_public_ip" {
  description = "Public IP of Cloud Gateway"
  value       = aws_instance.cloud_gateway.public_ip
}

output "cloud_gateway_private_ip" {
  description = "Private IP of Cloud Gateway"
  value       = aws_instance.cloud_gateway.private_ip
}

output "user_bff_public_ip" {
  description = "Public IP of User BFF"
  value       = aws_instance.user_bff.public_ip
}

output "user_bff_private_ip" {
  description = "Private IP of User BFF"
  value       = aws_instance.user_bff.private_ip
}

output "middleware_public_ip" {
  description = "Public IP of Middleware"
  value       = aws_instance.middleware.public_ip
}

output "middleware_private_ip" {
  description = "Private IP of Middleware"
  value       = aws_instance.middleware.private_ip
}

output "backend_public_ip" {
  description = "Public IP of Backend"
  value       = aws_instance.backend.public_ip
}

output "backend_private_ip" {
  description = "Private IP of Backend"
  value       = aws_instance.backend.private_ip
}

# =============================================================================
# Service URLs
# =============================================================================

output "gateway_url" {
  description = "URL for Cloud Gateway (main entry point)"
  value       = "http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}"
}

output "eureka_dashboard_url" {
  description = "URL for Eureka Dashboard"
  value       = "http://${aws_instance.eureka_server.public_ip}:${var.eureka_server_port}"
}

output "config_server_url" {
  description = "URL for Config Server"
  value       = "http://${aws_instance.config_server.public_ip}:${var.config_server_port}"
}

# =============================================================================
# API Endpoints
# =============================================================================

output "rest_endpoint" {
  description = "REST API endpoint"
  value       = "http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}/api/rest/hello?name=World"
}

output "soap_endpoint" {
  description = "SOAP API endpoint"
  value       = "http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}/ws"
}

output "graphql_endpoint" {
  description = "GraphQL API endpoint"
  value       = "http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}/graphql"
}

# =============================================================================
# SSH Information
# =============================================================================

output "ssh_private_key_path" {
  description = "Path to the SSH private key"
  value       = local_file.private_key.filename
}

output "ssh_command_config_server" {
  description = "SSH command to connect to Config Server"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.config_server.public_ip}"
}

output "ssh_command_eureka_server" {
  description = "SSH command to connect to Eureka Server"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.eureka_server.public_ip}"
}

output "ssh_command_cloud_gateway" {
  description = "SSH command to connect to Cloud Gateway"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.cloud_gateway.public_ip}"
}

output "ssh_command_user_bff" {
  description = "SSH command to connect to User BFF"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.user_bff.public_ip}"
}

output "ssh_command_middleware" {
  description = "SSH command to connect to Middleware"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.middleware.public_ip}"
}

output "ssh_command_backend" {
  description = "SSH command to connect to Backend"
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.backend.public_ip}"
}

# =============================================================================
# Sanity Report
# =============================================================================

output "sanity_report_json_path" {
  description = "Path to the sanity report JSON file"
  value       = "${abspath(path.module)}/sanity-report.json"
}

output "sanity_report_txt_path" {
  description = "Path to the sanity report TXT file"
  value       = "${abspath(path.module)}/sanity-report.txt"
}

# =============================================================================
# Test Commands
# =============================================================================

output "test_rest_command" {
  description = "Curl command to test REST endpoint"
  value       = "curl -s 'http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}/api/rest/hello?name=World'"
}

output "test_graphql_command" {
  description = "Curl command to test GraphQL endpoint"
  value       = "curl -s -X POST 'http://${aws_instance.cloud_gateway.public_ip}:${var.gateway_port}/graphql' -H 'Content-Type: application/json' -d '{\"query\": \"{ userStatus(id: \\\"1\\\") { status servedBy mtlsVerified clientCN } }\"}'"
}
