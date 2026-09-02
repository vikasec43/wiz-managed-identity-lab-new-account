# Wiz Managed Identity Abuse Lab
AWS Account: 139830186338 | Region: us-east-1

Engineer -> GitHub -> Jenkins -> ECR -> EC2 Docker workload -> wiz-lab-workload-role -> s3:GetObject -> synthetic confidential S3 object.

The IAM user wiz-lab-engineer intentionally has no S3 permissions. The EC2 role is the workload managed identity and has only GetObject on the lab object.
