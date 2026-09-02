resource "aws_ecr_repository" "workload" {
  name                 = "wiz-managed-identity-app"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
}
