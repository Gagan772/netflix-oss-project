# =============================================================================
# Netflix OSS Microservices Stack - IAM Configuration
# =============================================================================
# IAM resources are DISABLED for sandbox environments that don't allow IAM.
# If you need IAM, uncomment the resources below.
# =============================================================================

# # IAM Role for EC2 instances
# resource "aws_iam_role" "ec2_role" {
#   name = "${var.project_name}-ec2-role-${random_id.suffix.hex}"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       }
#     ]
#   })
#
#   tags = {
#     Name = "${var.project_name}-ec2-role"
#   }
# }

# # IAM Policy for EC2 instances
# resource "aws_iam_role_policy" "ec2_policy" {
#   name = "${var.project_name}-ec2-policy"
#   role = aws_iam_role.ec2_role.id
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "ec2:DescribeInstances",
#           "ec2:DescribeTags"
#         ]
#         Resource = "*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents",
#           "logs:DescribeLogStreams"
#         ]
#         Resource = "arn:aws:logs:*:*:*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "ssm:GetParameter",
#           "ssm:GetParameters",
#           "ssm:GetParametersByPath"
#         ]
#         Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
#       }
#     ]
#   })
# }

# # IAM Instance Profile
# resource "aws_iam_instance_profile" "ec2_profile" {
#   name = "${var.project_name}-ec2-profile-${random_id.suffix.hex}"
#   role = aws_iam_role.ec2_role.name
# }
