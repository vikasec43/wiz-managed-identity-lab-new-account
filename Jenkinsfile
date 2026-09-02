pipeline {
    agent any
    environment {
        AWS_REGION = 'us-east-1'
        AWS_ACCOUNT_ID = '139830186338'
        ECR_REPOSITORY = 'wiz-managed-identity-app'
        IMAGE_TAG = "${BUILD_NUMBER}"
        WORKLOAD_INSTANCE_ID = 'i-070eab68228c7a9ac'
    }
    stages {
        stage('Checkout') { steps { checkout scm } }
        stage('Build Docker Image') { steps { bat 'docker build -t %ECR_REPOSITORY%:%IMAGE_TAG% app' } }
        stage('Authenticate to ECR') {
            steps { withCredentials([[$class:'AmazonWebServicesCredentialsBinding', credentialsId:'wiz-lab-jenkins-aws']]) { bat 'aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com' } }
        }
        stage('Push Image') {
            steps { withCredentials([[$class:'AmazonWebServicesCredentialsBinding', credentialsId:'wiz-lab-jenkins-aws']]) { bat 'docker tag %ECR_REPOSITORY%:%IMAGE_TAG% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG% && docker push %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%' } }
        }
        stage('Deploy to EC2 through SSM') {
            steps {
                withCredentials([[$class:'AmazonWebServicesCredentialsBinding', credentialsId:'wiz-lab-jenkins-aws']]) {
                    bat 'aws ssm send-command --region %AWS_REGION% --instance-ids %WORKLOAD_INSTANCE_ID% --document-name AWS-RunShellScript --comment "Deploy Wiz lab application" --parameters "commands=[\"aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com\",\"docker pull %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%\",\"docker rm -f wiz-lab-app || true\",\"docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=wiz-managed-identity-lab-sensitive-139830186338 %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%\"]"'
                }
            }
        }
    }
}
