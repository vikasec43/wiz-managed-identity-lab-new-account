variable "aws_region" {
  description = "The AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account ID for the lab"
  type        = string
  default     = "139830186338"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "wiz-managed-identity-lab"
}

variable "sensitive_bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
  default     = "wiz-managed-identity-lab-sensitive-139830186338"
}

variable "allowed_ssh_cidr" {
  description = "Administrator public IPv4 address in CIDR notation"
  type        = string
  default     = "0.0.0.0/32"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}
