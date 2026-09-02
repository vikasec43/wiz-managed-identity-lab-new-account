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
                        echo ========================================
                        echo Verifying AWS Identity
                        echo ========================================

                        aws sts get-caller-identity
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                bat '''
                    echo ========================================
                    echo Building Docker Image
                    echo ========================================

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
                        echo ========================================
                        echo Authenticating to Amazon ECR
                        echo ========================================

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
                        echo ========================================
                        echo Tagging Docker Image
                        echo ========================================

                        docker tag %ECR_REPOSITORY%:%IMAGE_TAG% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%

                        echo ========================================
                        echo Pushing Image to ECR
                        echo ========================================

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
                    powershell '''
                        $ErrorActionPreference = "Stop"

                        $region = $env:AWS_REGION
                        $account = $env:AWS_ACCOUNT_ID
                        $repo = $env:ECR_REPOSITORY
                        $instance = $env:WORKLOAD_INSTANCE_ID
                        $bucket = $env:SENSITIVE_BUCKET
                        $tag = $env:IMAGE_TAG

                        $registry = "$account.dkr.ecr.$region.amazonaws.com"
                        $image = "$registry/$repo`:$tag"

                        Write-Host "========================================"
                        Write-Host "Deploying application to EC2"
                        Write-Host "========================================"
                        Write-Host "AWS Account : $account"
                        Write-Host "AWS Region  : $region"
                        Write-Host "EC2         : $instance"
                        Write-Host "Image       : $image"
                        Write-Host "S3 Bucket   : $bucket"

                        Write-Host ""
                        Write-Host "Checking AWS identity..."
                        aws sts get-caller-identity

                        Write-Host ""
                        Write-Host "Checking SSM managed instance..."
                        aws ssm describe-instance-information --region $region

                        Write-Host ""
                        Write-Host "Creating SSM command parameters..."

                        $commands = @(
                            "set -e",
                            "echo Starting Wiz Managed Identity application deployment",
                            "echo Logging in to Amazon ECR",
                            "aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry",
                            "echo Pulling application image",
                            "docker pull $image",
                            "echo Removing previous container",
                            "docker rm -f wiz-lab-app || true",
                            "echo Starting application container",
                            "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=$bucket $image",
                            "echo Checking container",
                            "docker ps --filter name=wiz-lab-app",
                            "echo Deployment completed successfully"
                        )

                        $parameters = @{
                            commands = $commands
                        } | ConvertTo-Json -Compress

                        Write-Host "Sending SSM command..."

                        $result = aws ssm send-command `
                            --region $region `
                            --instance-ids $instance `
                            --document-name "AWS-RunShellScript" `
                            --comment "Deploy Wiz Managed Identity Lab application" `
                            --parameters $parameters `
                            --output json | ConvertFrom-Json

                        $commandId = $result.Command.CommandId

                        if ([string]::IsNullOrWhiteSpace($commandId)) {
                            throw "SSM Command ID was not returned."
                        }

                        Write-Host ""
                        Write-Host "SSM Command ID: $commandId"
                        Write-Host "Waiting for deployment..."

                        $status = "Pending"

                        for ($i = 1; $i -le 36; $i++) {

                            Start-Sleep -Seconds 5

                            $invocation = aws ssm get-command-invocation `
                                --region $region `
                                --command-id $commandId `
                                --instance-id $instance `
                                --output json | ConvertFrom-Json

                            $status = $invocation.Status

                            Write-Host "SSM Status: $status"

                            if (
                                $status -eq "Success" -or
                                $status -eq "Failed" -or
                                $status -eq "Cancelled" -or
                                $status -eq "TimedOut"
                            ) {
                                break
                            }
                        }

                        Write-Host ""
                        Write-Host "========================================"
                        Write-Host "SSM DEPLOYMENT RESULT"
                        Write-Host "========================================"

                        Write-Host "Command ID: $commandId"
                        Write-Host "Status: $status"

                        $final = aws ssm get-command-invocation `
                            --region $region `
                            --command-id $commandId `
                            --instance-id $instance `
                            --output json | ConvertFrom-Json

                        Write-Host ""
                        Write-Host "----- Standard Output -----"

                        if ($final.StandardOutputContent) {
                            Write-Host $final.StandardOutputContent
                        }

                        Write-Host ""
                        Write-Host "----- Standard Error -----"

                        if ($final.StandardErrorContent) {
                            Write-Host $final.StandardErrorContent
                        }

                        Write-Host ""
                        Write-Host "========================================"

                        if ($status -ne "Success") {
                            throw "SSM deployment failed with status: $status"
                        }

                        Write-Host "DEPLOYMENT SUCCESSFUL"
                        Write-Host "========================================"
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
                    script {

                        echo "========================================"
                        echo "Verifying EC2 Deployment"
                        echo "========================================"

                        def result = powershell(
                            script: """
                                aws ssm describe-instance-information --region ${env.AWS_REGION}
                            """,
                            returnStdout: true
                        ).trim()

                        echo result

                        echo "Deployment verification completed."
                    }
                }
            }
        }
    }

    post {

        success {
            echo "========================================"
            echo "WIZ MANAGED IDENTITY LAB"
            echo "DEPLOYMENT SUCCESSFUL"
            echo "========================================"
        }

        failure {
            echo "========================================"
            echo "WIZ MANAGED IDENTITY LAB"
            echo "DEPLOYMENT FAILED"
            echo "Check Console Output for the failing stage."
            echo "========================================"
        }
    }
}