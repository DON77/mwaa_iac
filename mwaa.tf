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
# VPC for MWAA 
resource "aws_vpc" "default_vpc" {
  # default VPC imported
}

# Private subnet CIDRs in the var.private_subnets
resource "aws_subnet" "mwaa_private_subnet" {
  count                   = length(var.private_subnets)
  vpc_id                  = aws_vpc.default_vpc.id
  cidr_block              = var.private_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = var.common_tags
}

# Public Subnet Route Tables (imported as you mentioned)
# Assuming you already have a public route table, if not, use this part for public route table creation:
# resource "aws_route_table" "public_route_table" { ... }

#NAT gateway should be placed in public subnet, we will reuse existing one 
#  resource "aws_nat_gateway" "mwaa_nat_gateway" {
#   allocation_id = aws_eip.mwaa_nat_eip.id
#   subnet_id     = aws_subnet.mwaa_private_subnet[0].id  
#   tags = var.common_tags
# }

#Elastic IP for NAT Gateway
resource "aws_eip" "mwaa_nat_eip" {
  #vpc = true  # Make sure it's associated with your VPC
  domain = "vpc"
  tags = var.common_tags
}

# **Private Route Table** to route traffic via the NAT gateway
# resource "aws_route_table" "mwaa_private_route_table" {
#   vpc_id = aws_vpc.default_vpc.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     nat_gateway_id = var.nat_gateway
#   }
#   tags = var.common_tags
# }

# **Private Subnet Route Table Association** for the private subnets
resource "aws_route_table_association" "private_subnet_association" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.mwaa_private_subnet[count.index].id
  route_table_id = var.route_table_id
}
resource "aws_iam_role" "mwaa_role" {
  name = "mwaa-airflow-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = ["airflow-env.amazonaws.com","airflow.amazonaws.com"] 
        }
      }
    ]
  })
  tags = var.common_tags
}

# **IAM Policy for MWAA** 
resource "aws_iam_policy" "mwaa_policy" {
  name        = "mwaa-airflow-policy"
  description = "Policy for Airflow with necessary permissions"
  policy = jsonencode({
    "Version": "2012-10-17",
     "Statement": [
        {
            "Effect": "Allow",
            "Action": "airflow:PublishMetrics",
            "Resource": "arn:aws:airflow:${var.region}:${var.account_id}:environment/${aws_mwaa_environment.mwaa.name}*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject*",
                "s3:GetBucket*",
                "s3:List*",
                "s3:ListBucket",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "${aws_s3_bucket.mwaa_sync_bucket.arn}",
                "${aws_s3_bucket.mwaa_sync_bucket.arn}/*",
                 "${aws_s3_bucket.mwaa_sync_bucket.arn}/dags/*",
                 "${aws_s3_bucket.mwaa_sync_bucket.arn}/plugins/*",
                "${aws_s3_bucket.mwaa_sync_bucket.arn}/requirements/*",
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
                "arn:aws:logs:${var.region}:${var.account_id}:log-group:airflow-${aws_mwaa_environment.mwaa.name}-*",
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
        },
    ]
})

  tags = var.common_tags
  #depends_on = [ aws_s3_bucket.mwaa_sync_bucket ]
}

# **Attach IAM policy to MWAA role**
resource "aws_iam_role_policy_attachment" "mwaa_role_attachment" {
  policy_arn = aws_iam_policy.mwaa_policy.arn
  role       = aws_iam_role.mwaa_role.name
}

#**MWAA Environment Configuration**
resource "aws_mwaa_environment" "mwaa" {
  name               = "mwaa-env"
  environment_class  = "mw1.small"
  execution_role_arn = aws_iam_role.mwaa_role.arn
  source_bucket_arn  = aws_s3_bucket.mwaa_sync_bucket.arn
  dag_s3_path        = "dags/"
  

  plugins_s3_path    = "plugins/plugins.zip"
  requirements_s3_path = "requirements/requirements.txt"
  max_workers        = var.max_workers

  network_configuration {
    subnet_ids         = aws_subnet.mwaa_private_subnet[*].id
    security_group_ids = [var.security_group_id]

  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }

    task_logs {
      log_level = "INFO"
      enabled = true
    }  
    
    webserver_logs {
      log_level = "INFO"
      enabled = true
    }

    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  webserver_access_mode = "PUBLIC_ONLY"
  tags                  = var.common_tags
  airflow_configuration_options = {
    "webserver.warn_deployment_exposure" = "false"
    #"core.log_level" = "debug"
  }
  #depends_on =[aws_iam_role_policy_attachment.mwaa_role_attachment]
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
# resource "aws_security_group" "mwaa_sg" {
#   egress {
#     from_port        = 0
#     to_port          = 0
#     protocol         = "-1"
#     cidr_blocks      = ["0.0.0.0/0"]
#   }
#   ingress {
#     from_port        = 0
#     to_port          = 0
#     protocol         = "-1"
#     cidr_blocks      = ["0.0.0.0/0"]
#     self = true
#   }
#   ingress{
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = 443
#     protocol         = "tcp"
#     self             = true
#     to_port          = 443

#   }
#   ingress {
#     from_port        = 5432
#     to_port = 5432
#     protocol         = "tcp"
#     self = true
#   }
#   ingress {
#     from_port        = 8080
#     to_port = 8080
#     protocol         = "tcp"
#     self = true
#   }
#   #443 self should be added here or imported
#   name        = "mwaa-security-group"
#   revoke_rules_on_delete = false
#   description = "Security group for MWAA"
#   vpc_id      = aws_vpc.default_vpc.id
#   tags        = var.common_tags
  
# }

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
          Federated = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
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
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.mwaa_sync_bucket.arn}","${aws_s3_bucket.mwaa_sync_bucket.arn}/*"]
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

# import{
#   to = "mwaa_oidc_provider"
#   id = "arn:aws:iam::930985312118:oidc-provider/token.actions.githubusercontent.com"
# } 