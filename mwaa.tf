provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

terraform {
  backend "s3" {
    bucket         = "buycycle-mwaa-tf-state"
    key            = "terraform/state"
    region         = "eu-central-1"
    dynamodb_table = "buycycle-mwaa-tf-state-lock"
    encrypt        = true
  }
}

# Import public subnet CIDRs if necessary
# resource "aws_subnet" "public_subnet" { ... }  # This will be imported
# VPC for MWAA (assuming you have this already)
resource "aws_vpc" "default_vpc" {
  # Assuming you have a VPC, keep this part as is
}

# Private subnet CIDRs in the var.private_subnets
# resource "aws_subnet" "mwaa_private_subnet" {
#   count                   = length(var.private_subnets)
#   vpc_id                  = aws_vpc.default_vpc.id
#   cidr_block              = var.private_subnets[count.index]
#   availability_zone       = data.aws_availability_zones.available.names[count.index]
#   map_public_ip_on_launch = false
#   tags                    = var.common_tags
# }

# Public Subnet Route Tables (imported as you mentioned)
# Assuming you already have a public route table, if not, use this part for public route table creation:
# resource "aws_route_table" "public_route_table" { ... }

# resource "aws_nat_gateway" "mwaa_nat_gateway" {
#   #allocation_id = aws_eip.nat_eip.id
#   subnet_id     = var.public_subnets[0]  # Pick any of your public subnets
#   tags = var.common_tags
# }

# Elastic IP for NAT Gateway
# resource "aws_eip" "mwaa_nat_eip" {
#   #vpc = true  # Make sure it's associated with your VPC
#   domain = "vpc"
#   tags = var.common_tags
# }

# **Private Route Table** to route traffic via the NAT gateway
resource "aws_route_table" "mwaa_private_route_table" {
  vpc_id = aws_vpc.default_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway  # Pointing to NAT gateway
  }
  
  tags = var.common_tags
}

# **Private Subnet Route Table Association** for the private subnets
# resource "aws_route_table_association" "private_subnet_association" {
#   count          = length(var.private_subnets)
#   subnet_id      = aws_subnet.mwaa_private_subnet[count.index].id
#   route_table_id = aws_route_table.private_route_table.id
# }

# **MWAA Environment Configuration**
resource "aws_mwaa_environment" "mwaa" {
  name               = "mwaa-env"
  environment_class  = "mw1.small"
  execution_role_arn = aws_iam_role.mwaa_role.arn
  source_bucket_arn  = aws_s3_bucket.mwaa_sync_bucket.arn
  dag_s3_path        = "s3://mwaa_sync_bucket/dags"
  max_workers        = var.max_workers

  network_configuration {
    subnet_ids         = var.private_subnets[*]
    security_group_ids = [aws_security_group.mwaa_sg.id]
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "DEBUG"
    }

    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }

    task_logs {
      log_level = "WARNING"
    }

    webserver_logs {
      log_level = "ERROR"
    }

    worker_logs {
      enabled   = true
      log_level = "CRITICAL"
    }
  }

  webserver_access_mode = "PUBLIC_ONLY"
  tags                  = var.common_tags
}

# **IAM Role for MWAA**
resource "aws_iam_role" "mwaa_role" {
  name = "mwaa-airflow-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "airflow.amazonaws.com"
        }
      }
    ]
  })
  tags = var.common_tags
}

# **IAM Policy for MWAA** (S3 + RDS)
resource "aws_iam_policy" "mwaa_policy" {
  name        = "mwaa-airflow-policy"
  description = "Policy for Airflow with necessary permissions"

  # policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Action   = [
  #         "s3:ListBucket",
  #         "s3:GetObject",
  #         "s3:PutObject",
  #         "s3:DeleteObject"
  #       ]
  #       Effect   = "Allow"
  #       Resource = [
  #         aws_s3_bucket.mwaa_sync_bucket.arn,
  #         "${aws_s3_bucket.mwaa_sync_bucket.arn}/*"
  #       ]
  #     },
  #     {
  #       Action   = [
  #         "rds:DescribeDBInstances",
  #         "rds:DescribeDBClusters",
  #         "rds:Connect",
  #       ] 
  #       Effect   = "Allow"
  #       Resource = "*"
  #     },
  #     {
  #       Action = "secretsmanager:GetSecretValue",
  #       Effect = "Allow",
  #       Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:DB_*",
  #     },
  #     {
  #       Action   = "logs:CreateLogGroup"
  #       Effect   = "Allow"
  #       Resource = "*"
  #     },
  #     {
  #       Action   = "logs:CreateLogStream"
  #       Effect   = "Allow"
  #       Resource = "*"
  #     },
  #     {
  #       Action   = "logs:PutLogEvents"
  #       Effect   = "Allow"
  #       Resource = "*"
  #     }
  #   ]
  # })
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "airflow:PublishMetrics",
            "Resource": "arn:aws:airflow:${var.region}:${var.account_id}:environment/${aws_mwaa_environment.mwaa.name}"
        },
        {
            "Effect": "Deny",
            "Action": "s3:ListAllMyBuckets",
            "Resource": [
                "${aws_s3_bucket.mwaa_sync_bucket.arn}",
                "${aws_s3_bucket.mwaa_sync_bucket.arn}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject*",
                "s3:GetBucket*",
                "s3:List*"
            ],
            "Resource": [
                "${aws_s3_bucket.mwaa_sync_bucket.arn}",
                "${aws_s3_bucket.mwaa_sync_bucket.arn}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:CreateLogGroup",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:GetLogRecord",
                "logs:GetLogGroupFields",
                "logs:GetQueryResults"
            ],
            "Resource": [
                "arn:aws:logs:${var.region}:${var.account_id}:log-group:airflow-${aws_mwaa_environment.mwaa.name}-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogGroups"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetAccountPublicAccessBlock"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "cloudwatch:PutMetricData",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:ChangeMessageVisibility",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl",
                "sqs:ReceiveMessage",
                "sqs:SendMessage"
            ],
            "Resource": "arn:aws:sqs:${var.region}:*:airflow-celery-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:GenerateDataKey*",
                "kms:Encrypt"
            ],
            "NotResource": "arn:aws:kms:*:${var.account_id}:key/*",
            "Condition": {
                "StringLike": {
                    "kms:ViaService": [
                        "sqs.${var.region}.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:Connect",
                "rds:DescribeDBClusterEndpoints"
            ],
            "Resource": "arn:aws:rds:${var.region}:${var.account_id}:db:${var.prod_instance}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:DB*"
        }
    ]
})

  tags = var.common_tags
  depends_on = [ aws_s3_bucket.mwaa_sync_bucket ]
}

# **Attach IAM policy to MWAA role**
resource "aws_iam_role_policy_attachment" "mwaa_role_attachment" {
  policy_arn = aws_iam_policy.mwaa_policy.arn
  role       = aws_iam_role.mwaa_role.name
}

# **CloudWatch Log Groups (refactored to use dynamic naming based on MWAA environment)**
resource "aws_cloudwatch_log_group" "mwaa_task_log_group" {
  name  = "/aws/mwaa/env-${aws_mwaa_environment.mwaa.name}/task"
  tags  = var.common_tags
  depends_on = [ aws_mwaa_environment.mwaa ]
}

resource "aws_cloudwatch_log_group" "mwaa_webserver_log_group" {
  name  = "/aws/mwaa/env-${aws_mwaa_environment.mwaa.name}/webserver"
  tags  = var.common_tags
  depends_on = [ aws_mwaa_environment.mwaa ]
}

# S3 bucket for MWAA sync
resource "aws_s3_bucket" "mwaa_sync_bucket" {
  bucket = "mwaa-sync-bucket"
  tags   = var.common_tags
  
}
resource "aws_s3_bucket_versioning" "mwaa_versioning" {
  bucket = aws_s3_bucket.mwaa_sync_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Security group for MWAA
resource "aws_security_group" "mwaa_sg" {
  name        = "mwaa-security-group"
  description = "Security group for MWAA"
  vpc_id      = aws_vpc.default_vpc.id
  tags        = var.common_tags
}

# IAM Role for GitHub Actions to assume (OIDC)
resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::aws:policy/AWSWebIdentity"
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:buycycle/data:*"
          }
        }
      }
    ]
  })
  tags = var.common_tags
}

# GitHub Actions policy for accessing S3
resource "aws_iam_policy" "github_actions_policy" {
  name        = "GitHubActionsPolicy"
  description = "Custom policy for GitHub Actions to access AWS services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject", 
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.mwaa_sync_bucket.arn}/*"
      }
    ]
  })
  tags = var.common_tags
}

# Attach GitHub Actions policy to the role
resource "aws_iam_role_policy_attachment" "github_actions_role_policy" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}