output "vpc_id" {
  value = aws_vpc.lab.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_id" {
  value = aws_security_group.ec2.id
}

output "ec2_instance_id" {
  value = aws_instance.workload.id
}

output "ec2_public_ip" {
  value = aws_instance.workload.public_ip
}

output "s3_sensitive_bucket" {
  value = aws_s3_bucket.sensitive.bucket
}

output "sensitive_object_arn" {
  value = "${aws_s3_bucket.sensitive.arn}/production/customer-records.txt"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "workload_role_arn" {
  value = aws_iam_role.workload.arn
}

output "engineer_user_arn" {
  value = aws_iam_user.engineer.arn
}

output "jenkins_user_arn" {
  value = aws_iam_user.jenkins.arn
}
