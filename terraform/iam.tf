# -----------------------------
# EC2 workload managed identity
# -----------------------------

resource "aws_iam_role" "workload" {
  name        = "wiz-lab-workload-role"
  description = "Managed identity for the Wiz managed identity abuse lab workload"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "wiz-lab-workload-role"
  }
}

# Workload can read the lab object and list/get bucket metadata, matching the old lab.
resource "aws_iam_role_policy" "sensitive_s3" {
  name = "wiz-lab-sensitive-s3-access"
  role = aws_iam_role.workload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabSensitiveData"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.sensitive.arn,
          "${aws_s3_bucket.sensitive.arn}/*"
        ]
      }
    ]
  })
}

# EC2 pulls the Docker image from ECR.
resource "aws_iam_role_policy" "ecr_pull" {
  name = "wiz-lab-ecr-pull"
  role = aws_iam_role.workload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthorization"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.workload.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "workload" {
  name = "wiz-lab-workload-profile"
  role = aws_iam_role.workload.name
}

resource "aws_iam_role_policy" "ssm_parameters_read" {
  name = "wiz-lab-read-configuration"
  role = aws_iam_role.workload.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabConfiguration"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = aws_ssm_parameter.sensitive_bucket.arn
      }
    ]
  })
}

# -----------------------------
# Engineer identity
# -----------------------------
# Intentionally NO S3 policy is attached to this user.
resource "aws_iam_user" "engineer" {
  name = "wiz-lab-engineer"

  tags = {
    Name = "wiz-lab-engineer"
  }
}

# -----------------------------
# Jenkins identity
# -----------------------------
resource "aws_iam_user" "jenkins" {
  name = "wiz-lab-jenkins"

  tags = {
    Name = "wiz-lab-jenkins"
  }
}

data "aws_iam_policy_document" "jenkins" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrRepositoryPush"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage"
    ]

    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid    = "DeployThroughSsm"
    effect = "Allow"

    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DescribeForDeployment"
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "jenkins" {
  name   = "wiz-lab-jenkins-deploy-policy"
  user   = aws_iam_user.jenkins.name
  policy = data.aws_iam_policy_document.jenkins.json
}
