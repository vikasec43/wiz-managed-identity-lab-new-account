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

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                bat '''
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
                    aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com
                    '''
                }
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat '''
                    docker tag %ECR_REPOSITORY%:%IMAGE_TAG% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%

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

                    # -------------------------------------------------
                    # Build ECR variables
                    # -------------------------------------------------

                    $region = $env:AWS_REGION
                    $accountId = $env:AWS_ACCOUNT_ID
                    $repository = $env:ECR_REPOSITORY
                    $tag = $env:IMAGE_TAG
                    $instanceId = $env:WORKLOAD_INSTANCE_ID

                    $registry = "${accountId}.dkr.ecr.${region}.amazonaws.com"
                    $image = "${registry}/${repository}:${tag}"

                    Write-Host ""
                    Write-Host "========================================"
                    Write-Host "Deployment Information"
                    Write-Host "========================================"
                    Write-Host "AWS Region       : $region"
                    Write-Host "ECR Repository   : $repository"
                    Write-Host "Image Tag        : $tag"
                    Write-Host "Workload EC2     : $instanceId"
                    Write-Host "ECR Image        : $image"
                    Write-Host "========================================"
                    Write-Host ""

                    # -------------------------------------------------
                    # Verify Jenkins AWS identity
                    # -------------------------------------------------

                    Write-Host "Verifying Jenkins AWS credentials..."

                    aws sts get-caller-identity --region $region

                    if ($LASTEXITCODE -ne 0) {
                        throw "Unable to verify Jenkins AWS credentials."
                    }

                    # -------------------------------------------------
                    # Create commands that will execute ON EC2
                    # -------------------------------------------------

                    $commands = @(
                        "set -e",
                        "echo 'Starting Wiz Managed Identity application deployment...'",
                        "echo 'Logging in to Amazon ECR...'",
                        "aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${registry}",
                        "echo 'Pulling image ${image}...'",
                        "docker pull ${image}",
                        "echo 'Removing existing container if present...'",
                        "docker rm -f wiz-lab-app || true",
                        "echo 'Starting new application container...'",
                        "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=wiz-managed-identity-lab-sensitive-139830186338 ${image}",
                        "echo 'Checking running container...'",
                        "docker ps --filter name=wiz-lab-app",
                        "echo 'Deployment completed on EC2.'"
                    )

                    # -------------------------------------------------
                    # Create SSM parameter JSON
                    # -------------------------------------------------

                    $parameters = @{
                        commands = $commands
                    }

                    $parameters | ConvertTo-Json -Compress | Set-Content `
                        -Path "ssm-parameters.json" `
                        -Encoding ascii

                    Write-Host ""
                    Write-Host "SSM parameter file:"
                    Get-Content "ssm-parameters.json"
                    Write-Host ""

                    # -------------------------------------------------
                    # Send command to EC2 through SSM
                    # -------------------------------------------------

                    Write-Host "Sending deployment command to EC2..."

                    $commandJson = aws ssm send-command `
                        --region $region `
                        --instance-ids $instanceId `
                        --document-name "AWS-RunShellScript" `
                        --comment "Deploy Wiz managed identity application" `
                        --parameters "file://ssm-parameters.json" `
                        --output json

                    if ($LASTEXITCODE -ne 0) {
                        throw "AWS SSM send-command failed."
                    }

                    $command = $commandJson | ConvertFrom-Json
                    $commandId = $command.Command.CommandId

                    if ([string]::IsNullOrWhiteSpace($commandId)) {
                        throw "SSM did not return a command ID."
                    }

                    Write-Host ""
                    Write-Host "SSM Command ID: $commandId"
                    Write-Host ""

                    # -------------------------------------------------
                    # Wait for SSM command to finish
                    # -------------------------------------------------

                    Write-Host "Waiting for EC2 deployment to complete..."

                    $status = "Pending"
                    $result = $null

                    for ($i = 1; $i -le 36; $i++) {

                        Start-Sleep -Seconds 5

                        $resultJson = aws ssm get-command-invocation `
                            --region $region `
                            --command-id $commandId `
                            --instance-id $instanceId `
                            --output json 2>$null

                        if ($LASTEXITCODE -eq 0 -and $resultJson) {

                            $result = $resultJson | ConvertFrom-Json
                            $status = $result.Status

                            Write-Host "SSM Status: $status"

                            if ($status -in @(
                                "Success",
                                "Failed",
                                "Cancelled",
                                "TimedOut",
                                "Cancelling"
                            )) {
                                break
                            }
                        }
                        else {
                            Write-Host "SSM command is still being initialized..."
                        }
                    }

                    # -------------------------------------------------
                    # Display SSM results
                    # -------------------------------------------------

                    Write-Host ""
                    Write-Host "========================================"
                    Write-Host "SSM DEPLOYMENT RESULT"
                    Write-Host "========================================"
                    Write-Host "Command ID : $commandId"
                    Write-Host "Status     : $status"
                    Write-Host ""

                    if ($result) {

                        Write-Host "----- Standard Output -----"
                        Write-Host $result.StandardOutputContent

                        Write-Host ""
                        Write-Host "----- Standard Error -----"
                        Write-Host $result.StandardErrorContent

                        Write-Host ""
                        Write-Host "----- Response Code -----"
                        Write-Host $result.ResponseCode
                    }

                    Write-Host "========================================"
                    Write-Host ""

                    # -------------------------------------------------
                    # Fail Jenkins if deployment failed
                    # -------------------------------------------------

                    if ($status -ne "Success") {
                        throw "EC2 deployment failed. SSM final status: $status"
                    }

                    Write-Host "========================================"
                    Write-Host "DEPLOYMENT SUCCESSFUL"
                    Write-Host "========================================"
                }
            }
        }
    }

    post {
        always {
            powershell '''
            if (Test-Path "ssm-parameters.json") {
                Remove-Item "ssm-parameters.json" -Force
                Write-Host "Temporary SSM parameter file removed."
            }
            '''
        }

        success {
            echo 'Wiz Managed Identity Lab deployment completed successfully.'
        }

        failure {
            echo 'Wiz Managed Identity Lab deployment failed. Check the stage output above.'
        }
    }
}