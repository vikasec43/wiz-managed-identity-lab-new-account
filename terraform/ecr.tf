resource "aws_ecr_repository" "app" {
  name                 = "wiz-managed-identity-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "Wiz Managed Identity Application"
  }
}
