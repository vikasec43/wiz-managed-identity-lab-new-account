resource "aws_security_group" "workload" {
  name        = "wiz-lab-workload-sg"
  description = "Security group for Wiz managed identity lab workload"
  vpc_id      = aws_vpc.main.id
  ingress {
    description = "Intentional lab exposure for attack-path demonstration"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_instance" "workload" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.workload.id
  vpc_security_group_ids      = [aws_security_group.workload.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.workload.name
  user_data                   = <<-EOT
#!/bin/bash
set -eux
dnf update -y
dnf install -y docker awscli2
systemctl enable --now docker
usermod -aG docker ec2-user
mkdir -p /opt/wiz-lab
chown ec2-user:ec2-user /opt/wiz-lab
echo 'Wiz managed identity lab workload initialized' > /opt/wiz-lab/README.txt
EOT
  tags                        = { Name = "wiz-lab-workload-ec2", Role = "workload" }
  depends_on                  = [aws_iam_role_policy.workload_s3_read, aws_iam_role_policy_attachment.ssm, aws_iam_role_policy_attachment.ecr_read]
}
