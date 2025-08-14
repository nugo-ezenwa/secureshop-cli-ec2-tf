variable "project" {
  type        = string
  default     = "secureshop"
  description = "Project prefix"
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Admin CLI EC2 size"
}

variable "cluster_name" {
  type        = string
  default     = "secureshop-eks"
  description = "EKS cluster name (for convenience env)"
}

variable "trivy_version" {
  type        = string
  default     = "0.54.1"
  description = "Trivy version (as string)"
}
