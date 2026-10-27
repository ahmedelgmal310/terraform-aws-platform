# Deliberately insecure configuration. CI plans it (never applies it) and
# expects the Conftest policies to reject it; the job fails if any expected
# violation is missing. It is excluded from Checkov for the same reason.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = "policy-fixture"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_s3_bucket" "public" {
  bucket = "policy-fixture-public-bucket"
}

resource "aws_s3_bucket_acl" "public" {
  bucket = aws_s3_bucket.public.id
  acl    = "public-read"
}

resource "aws_vpc" "this" {
  cidr_block = "10.99.0.0/16"
}

resource "aws_security_group" "ssh_world" {
  name        = "ssh-from-anywhere"
  description = "Insecure fixture"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh_world" {
  security_group_id = aws_security_group.ssh_world.id
  description       = "SSH from anywhere"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_instance" "oversized" {
  identifier                  = "policy-fixture-db"
  engine                      = "postgres"
  instance_class              = "db.r7g.4xlarge"
  allocated_storage           = 20
  username                    = "fixture"
  manage_master_user_password = true
  storage_encrypted           = false
  publicly_accessible         = true
  backup_retention_period     = 0
  skip_final_snapshot         = true
}

resource "aws_iam_role" "github_any_repo" {
  name = "policy-fixture-github"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = "arn:aws:iam::000000000000:oidc-provider/token.actions.githubusercontent.com" }
      Condition = {
        StringLike = { "token.actions.githubusercontent.com:sub" = "repo:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "admin" {
  name = "admin"
  role = aws_iam_role.github_any_repo.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}

resource "aws_kms_key" "no_rotation" {
  description         = "Insecure fixture"
  enable_key_rotation = false
}

resource "aws_cloudwatch_log_group" "plaintext" {
  name              = "/policy-fixture/plaintext"
  retention_in_days = 7
}
