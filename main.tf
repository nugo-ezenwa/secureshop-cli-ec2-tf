terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Useful identity/partition/VPC lookups
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "default" {
  default = true
}

# --- IAM role for EC2 (SSM + minimal ECR/EKS) ---
resource "aws_iam_role" "admin_cli" {
  name = "${var.project}-admin-cli-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        # Works across partitions (e.g., aws / aws-cn)
        Service = "ec2.${data.aws_partition.current.dns_suffix}"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.admin_cli.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "minimal" {
  name = "${var.project}-admin-cli-minimal"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # ECR (pull/push images if needed)
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ],
        Resource = "*"
      },
      # EKS describe for kubeconfig generation
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      },
      # Optional S3/DynamoDB if you ever run TF on the instance
      {
        Effect   = "Allow",
        Action   = ["s3:*"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["dynamodb:*"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "minimal_attach" {
  role       = aws_iam_role.admin_cli.name
  policy_arn = aws_iam_policy.minimal.arn
}

resource "aws_iam_instance_profile" "admin_cli" {
  name = "${var.project}-admin-cli-profile"
  role = aws_iam_role.admin_cli.name
}

# --- Security group (no inbound; SSM only) ---
resource "aws_security_group" "admin_cli" {
  name        = "${var.project}-admin-cli-sg"
  description = "Admin CLI EC2; SSM access only"
  vpc_id      = data.aws_vpc.default.id

  # No inbound rules (SSM uses outbound to reach AWS endpoints)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-admin-cli"
  }
}

# --- User data / cloud-init ---
locals {
  cloud_init = <<-EOF
  #!/bin/bash
  set -euxo pipefail
  dnf -y update
  dnf -y install git unzip docker awscli jq
  systemctl enable --now docker
  usermod -aG docker ec2-user

  # Terraform
  dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  dnf -y install terraform

  # kubectl
  curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl

  # helm
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  # yq
  curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq

  # trivy (tolerate version mismatches)
  rpm -ivh https://github.com/aquasecurity/trivy/releases/latest/download/trivy_${var.trivy_version}_Linux-64bit.rpm || true

  # cosign
  curl -L https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o /usr/local/bin/cosign
  chmod +x /usr/local/bin/cosign

  # convenience env
  cat >/etc/profile.d/secureshop.sh <<'SHP'
  export AWS_REGION="${var.region}"
  export CLUSTER_NAME="${var.cluster_name}"
  SHP

  echo "bootstrap-complete" > /var/log/secureshop-bootstrap.log
  EOF
}

# --- Latest Amazon Linux 2023 AMI (x86_64) ---
data "aws_ami" "al2023" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- EC2 instance ---
resource "aws_instance" "admin_cli" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.admin_cli.name
  vpc_security_group_ids = [aws_security_group.admin_cli.id]
  user_data              = local.cloud_init

  tags = {
    Name    = "${var.project}-admin-cli"
    Project = var.project
  }
}

# --- Outputs ---
output "admin_cli_instance_id" {
  value = aws_instance.admin_cli.id
}

output "admin_cli_public_ip" {
  value = aws_instance.admin_cli.public_ip
}

output "admin_cli_role" {
  value = aws_iam_role.admin_cli.name
}