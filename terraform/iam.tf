data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "workload" {
  name               = "wiz-lab-workload-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Managed identity for the Wiz managed identity abuse lab workload"
}
resource "aws_iam_instance_profile" "workload" {
  name = "wiz-lab-workload-instance-profile"
  role = aws_iam_role.workload.name
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.workload.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.workload.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy" "workload_s3_read" {
  name   = "ReadOnlySpecificSensitiveObject"
  role   = aws_iam_role.workload.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.sensitive.arn}/production/customer-records.txt" }] })
}
resource "aws_iam_user" "engineer" { name = "wiz-lab-engineer" }
resource "aws_iam_user" "jenkins" { name = "wiz-lab-jenkins" }
data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid       = "EcrRepositoryPush"
    effect    = "Allow"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
    resources = [aws_ecr_repository.workload.arn]
  }
  statement {
    sid       = "DeployThroughSsm"
    effect    = "Allow"
    actions   = ["ssm:SendCommand", "ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands"]
    resources = ["*"]
  }
  statement {
    sid       = "DescribeForDeployment"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation"]
    resources = ["*"]
  }
}
resource "aws_iam_user_policy" "jenkins" {
  name   = "wiz-lab-jenkins-deploy-policy"
  user   = aws_iam_user.jenkins.name
  policy = data.aws_iam_policy_document.jenkins.json
}
