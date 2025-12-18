# =============================================================================
# Netflix OSS Microservices Stack - EC2 Instances
# =============================================================================

# =============================================================================
# Config Server Instance
# =============================================================================

resource "aws_instance" "config_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.config_server.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/config-server.sh", {
    service_name = "config-server"
    service_port = var.config_server_port
    service_user = "svc_config"
  }))

  tags = {
    Name    = "${var.project_name}-config-server"
    Service = "config-server"
  }

  depends_on = [aws_nat_gateway.main]
}

# =============================================================================
# Eureka Server Instance
# =============================================================================

resource "aws_instance" "eureka_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.eureka_server.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/eureka-server.sh", {
    service_name = "eureka-server"
    service_port = var.eureka_server_port
    service_user = "svc_eureka"
    config_host  = aws_instance.config_server.private_ip
    config_port  = var.config_server_port
  }))

  tags = {
    Name    = "${var.project_name}-eureka-server"
    Service = "eureka-server"
  }

  depends_on = [aws_instance.config_server]
}

# =============================================================================
# Backend Instance
# =============================================================================

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.backend.id]


  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/backend.sh", {
    service_name = "backend"
    service_port = var.backend_port
    service_user = "svc_backend"
    config_host  = aws_instance.config_server.private_ip
    config_port  = var.config_server_port
    eureka_host  = aws_instance.eureka_server.private_ip
    eureka_port  = var.eureka_server_port
  }))

  tags = {
    Name    = "${var.project_name}-backend"
    Service = "backend"
  }

  depends_on = [aws_instance.eureka_server]
}

# =============================================================================
# Middleware Instance
# =============================================================================

resource "aws_instance" "middleware" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.middleware.id]


  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/middleware.sh", {
    service_name = "middleware"
    service_port = var.middleware_port
    service_user = "svc_middleware"
    config_host  = aws_instance.config_server.private_ip
    config_port  = var.config_server_port
    eureka_host  = aws_instance.eureka_server.private_ip
    eureka_port  = var.eureka_server_port
    backend_host = aws_instance.backend.private_ip
    backend_port = var.backend_port
    ca_cert      = local.ca_cert_content
    server_cert  = local.middleware_server_cert
    server_key   = local.middleware_server_key
  }))

  tags = {
    Name    = "${var.project_name}-middleware"
    Service = "middleware"
  }

  depends_on = [aws_instance.backend]
}

# =============================================================================
# User BFF Instance
# =============================================================================

resource "aws_instance" "user_bff" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.user_bff.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/user-bff.sh", {
    service_name     = "user-bff"
    service_port     = var.user_bff_port
    service_user     = "svc_userbff"
    config_host      = aws_instance.config_server.private_ip
    config_port      = var.config_server_port
    eureka_host      = aws_instance.eureka_server.private_ip
    eureka_port      = var.eureka_server_port
    middleware_host  = aws_instance.middleware.private_ip
    middleware_port  = var.middleware_port
    ca_cert          = local.ca_cert_content
    client_cert      = local.userbff_client_cert
    client_key       = local.userbff_client_key
  }))

  tags = {
    Name    = "${var.project_name}-user-bff"
    Service = "user-bff"
  }

  depends_on = [aws_instance.middleware]
}

# =============================================================================
# Cloud Gateway Instance
# =============================================================================

resource "aws_instance" "cloud_gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.cloud_gateway.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/provisioning/cloud-gateway.sh", {
    service_name  = "cloud-gateway"
    service_port  = var.gateway_port
    service_user  = "svc_gateway"
    config_host   = aws_instance.config_server.private_ip
    config_port   = var.config_server_port
    eureka_host   = aws_instance.eureka_server.private_ip
    eureka_port   = var.eureka_server_port
    user_bff_host = aws_instance.user_bff.private_ip
    user_bff_port = var.user_bff_port
  }))

  tags = {
    Name    = "${var.project_name}-cloud-gateway"
    Service = "cloud-gateway"
  }

  depends_on = [aws_instance.user_bff]
}

# =============================================================================
# Wait for Services to be Ready
# =============================================================================

resource "null_resource" "wait_for_services" {
  depends_on = [
    aws_instance.config_server,
    aws_instance.eureka_server,
    aws_instance.cloud_gateway,
    aws_instance.user_bff,
    aws_instance.middleware,
    aws_instance.backend
  ]

  provisioner "local-exec" {
    command     = "Write-Host 'Waiting for services to start (this may take 8-10 minutes)...'; Start-Sleep -Seconds 480; Write-Host 'Initial wait complete.'"
    interpreter = ["PowerShell", "-Command"]
  }
}

# =============================================================================
# Sanity Check
# =============================================================================

resource "null_resource" "sanity_check" {
  depends_on = [null_resource.wait_for_services]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = <<-EOT
      $gateway_ip = "${aws_instance.cloud_gateway.public_ip}"
      $gateway_port = "${var.gateway_port}"
      $report_path = "${path.module}/sanity-report.txt"
      
      Write-Host "Running sanity checks against http://$gateway_ip`:$gateway_port"
      
      $results = @()
      $passed = 0
      $failed = 0
      
      # Test REST endpoint
      try {
        $response = Invoke-RestMethod -Uri "http://$gateway_ip`:$gateway_port/api/users/health" -TimeoutSec 30
        $results += "REST Health: PASSED"
        $passed++
      } catch {
        $results += "REST Health: FAILED - $($_.Exception.Message)"
        $failed++
      }
      
      # Test REST data endpoint
      try {
        $body = @{name="TestUser";email="test@example.com"} | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "http://$gateway_ip`:$gateway_port/api/users/data" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 30
        if ($response.servedBy -eq "backend") {
          $results += "REST->Middleware->Backend: PASSED"
          $passed++
        } else {
          $results += "REST->Middleware->Backend: FAILED - Unexpected response"
          $failed++
        }
      } catch {
        $results += "REST->Middleware->Backend: FAILED - $($_.Exception.Message)"
        $failed++
      }
      
      # Test GraphQL endpoint
      try {
        $gqlBody = @{query="{ health }"} | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "http://$gateway_ip`:$gateway_port/api/users/graphql" -Method POST -Body $gqlBody -ContentType "application/json" -TimeoutSec 30
        $results += "GraphQL Health: PASSED"
        $passed++
      } catch {
        $results += "GraphQL Health: FAILED - $($_.Exception.Message)"
        $failed++
      }
      
      # Generate report
      $report = "Netflix OSS Sanity Check Report`n"
      $report += "================================`n"
      $report += "Gateway: http://$gateway_ip`:$gateway_port`n"
      $report += "Timestamp: $(Get-Date)`n"
      $report += "`nResults:`n"
      $results | ForEach-Object { $report += "  - $_`n" }
      $report += "`nSummary: $passed passed, $failed failed`n"
      
      $report | Out-File -FilePath $report_path -Encoding UTF8
      Write-Host $report
      
      if ($failed -gt 0) { exit 1 }
    EOT
    interpreter = ["PowerShell", "-Command"]
  }
}
