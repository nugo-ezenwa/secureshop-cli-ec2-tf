# Admin CLI EC2 via Terraform

This module launches an **Amazon Linux 2023** EC2 instance preloaded with DevSecOps CLIs via **cloud-init**:
- Terraform, kubectl, Helm, Docker, jq, yq
- Trivy (image scanner), Cosign (image signing)
- IAM Instance Profile with **SSM**, ECR access, EKS describe

## Usage
```hcl
module "admin_cli" {
  source        = "./secureshop-cli-ec2-tf"
  region        = "us-east-1"
  project       = "secureshop"
  instance_type = "t3.medium"
  cluster_name  = "secureshop-eks"
}
```
Then:
```bash
terraform init && terraform apply -auto-approve
```

## Access the instance
Prefer **SSM Session Manager** (no SSH needed):
```bash
aws ssm start-session --target <INSTANCE_ID>
```
If you must SSH, attach a key pair and open port 22 yourself (not recommended).

## Verify CLIs
```bash
kubectl version --client
helm version
terraform version
trivy --version
cosign version
```
