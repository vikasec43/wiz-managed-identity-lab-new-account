pipeline {
    agent any

    environment {
        AWS_REGION           = 'us-east-1'
        AWS_ACCOUNT_ID       = '139830186338'
        ECR_REPOSITORY       = 'wiz-managed-identity-app'
        IMAGE_TAG            = "${BUILD_NUMBER}"
        WORKLOAD_INSTANCE_ID = 'i-02e8dd862397203ad'
        SENSITIVE_BUCKET     = 'wiz-managed-identity-lab-sensitive-139830186338'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Verify AWS Identity') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                        echo Verifying AWS identity...
                        aws sts get-caller-identity
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                bat '''
                    echo Building Docker image...
                    docker build -t %ECR_REPOSITORY%:%IMAGE_TAG% app
                '''
            }
        }

        stage('Authenticate to ECR') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                        echo Authenticating to Amazon ECR...
                        aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com
                    '''
                }
            }
        }

        stage('Push Image to ECR') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                        echo Tagging Docker image...
                        docker tag %ECR_REPOSITORY%:%IMAGE_TAG% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%

                        echo Pushing Docker image to ECR...
                        docker push %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%
                    '''
                }
            }
        }

        stage('Deploy to EC2 through SSM') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                        echo Deploying application to EC2...
                        echo Instance: %WORKLOAD_INSTANCE_ID%

                        aws ssm send-command ^
                          --region %AWS_REGION% ^
                          --instance-ids %WORKLOAD_INSTANCE_ID% ^
                          --document-name AWS-RunShellScript ^
                          --comment "Deploy Wiz managed identity lab application" ^
                          --parameters "commands=[\"aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com\",\"docker pull %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%\",\"docker rm -f wiz-lab-app || true\",\"docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=%SENSITIVE_BUCKET% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%\"]"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                        echo Checking SSM command status...
                        aws ssm list-command-invocations ^
                          --region %AWS_REGION% ^
                          --details ^
                          --max-items 1
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Wiz Managed Identity Lab deployment completed successfully.'
        }

        failure {
            echo 'Deployment failed. Check the Jenkins Console Output for the failing stage.'
        }
    }
}