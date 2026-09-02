provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = "wiz-managed-identity-lab", Environment = "demo", ManagedBy = "Terraform" } }
}
data "aws_caller_identity" "current" {}
data "aws_ssm_parameter" "al2023_ami" { name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" }
