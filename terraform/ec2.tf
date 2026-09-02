# Create EC2 using the same structure as the previous lab.

resource "aws_instance" "workload" {
  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.workload.name

  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    dnf update -y
    dnf install -y docker awscli2

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ec2-user

    mkdir -p /opt/wiz-lab
    chown ec2-user:ec2-user /opt/wiz-lab

    echo "Wiz Managed Identity Lab initialized" > /tmp/wiz-lab.txt
    echo "Workload role: wiz-lab-workload-role" > /opt/wiz-lab/README.txt
  EOF

  tags = {
    Name        = "wiz-lab-workload"
    Environment = "PRODUCTION-LAB"
    Project     = var.project_name
  }

  depends_on = [
    aws_iam_role_policy.sensitive_s3,
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy_attachment.ssm
  ]
}
