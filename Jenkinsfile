pipeline {
    agent any

    environment {
        AWS_REGION           = 'us-east-1'
        AWS_ACCOUNT_ID       = '139830186338'
        ECR_REPOSITORY       = 'wiz-managed-identity-app'
        IMAGE_TAG            = "${BUILD_NUMBER}"
        WORKLOAD_INSTANCE_ID = 'i-02e8dd862397203ad'
        SENSITIVE_BUCKET     = 'wiz-managed-identity-lab-sensitive-139830186338'
        JENKINS_AWS_CREDENTIAL = 'wiz-lab-jenkins-aws'
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
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {
                    bat '''
                        echo ========================================
                        echo AWS IDENTITY
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
                    echo BUILDING DOCKER IMAGE
                    echo ========================================

                    docker build -t %ECR_REPOSITORY%:%IMAGE_TAG% app
                '''
            }
        }

        stage('Authenticate to ECR') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {
                    bat '''
                        echo ========================================
                        echo AUTHENTICATING TO ECR
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
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {
                    bat '''
                        echo ========================================
                        echo PUSHING IMAGE TO ECR
                        echo ========================================

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
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {

                    script {

                        def registry =
                            "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                        def image =
                            "${registry}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                        echo "========================================"
                        echo "EC2 DEPLOYMENT"
                        echo "========================================"
                        echo "Instance : ${env.WORKLOAD_INSTANCE_ID}"
                        echo "Image    : ${image}"
                        echo "Region   : ${env.AWS_REGION}"
                        echo "========================================"

                        /*
                         * Commands executed on Amazon Linux EC2.
                         *
                         * SSM runs these commands as root.
                         *
                         * Docker is installed automatically if it
                         * is not already installed.
                         */

                        def commands = [
                            "set -e",
                            "echo 'Starting EC2 deployment'",
                            "echo 'Checking operating system'",
                            "cat /etc/os-release",
                            "echo 'Checking Docker installation'",
                            "if ! command -v docker >/dev/null 2>&1; then echo 'Docker not found - installing Docker'; dnf install -y docker; fi",
                            "echo 'Enabling Docker service'",
                            "systemctl enable docker",
                            "echo 'Starting Docker service'",
                            "systemctl start docker",
                            "echo 'Checking Docker status'",
                            "systemctl is-active docker",
                            "docker --version",
                            "echo 'Checking AWS CLI'",
                            "aws --version",
                            "echo 'Logging in to Amazon ECR'",
                            "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${registry}",
                            "echo 'Pulling Docker image'",
                            "docker pull ${image}",
                            "echo 'Removing previous application container'",
                            "docker rm -f wiz-lab-app || true",
                            "echo 'Starting application container'",
                            "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=${env.SENSITIVE_BUCKET} ${image}",
                            "echo 'Waiting for container to start'",
                            "sleep 5",
                            "echo 'Checking running containers'",
                            "docker ps --filter name=wiz-lab-app",
                            "echo 'Checking application container logs'",
                            "docker logs --tail 50 wiz-lab-app",
                            "echo 'Deployment completed successfully'"
                        ]

                        /*
                         * Convert commands into JSON.
                         *
                         * JsonOutput.toJson is used so that the JSON
                         * is correctly escaped.
                         */

                        def jsonCommands =
                            groovy.json.JsonOutput.toJson([
                                commands: commands
                            ])

                        writeFile(
                            file: 'ssm-parameters.json',
                            text: jsonCommands
                        )

                        echo "SSM parameter file created."

                        /*
                         * Send command to EC2.
                         */

                        powershell """
                            \$ErrorActionPreference = 'Stop'

                            Write-Host 'Sending SSM command...'

                            \$result = aws ssm send-command `
                                --region '${env.AWS_REGION}' `
                                --instance-ids '${env.WORKLOAD_INSTANCE_ID}' `
                                --document-name 'AWS-RunShellScript' `
                                --comment 'Deploy Wiz Managed Identity Lab application' `
                                --parameters file://ssm-parameters.json `
                                --output json

                            \$result | Out-File -FilePath 'ssm-command.json' -Encoding utf8

                            \$commandId = (\$result | ConvertFrom-Json).Command.CommandId

                            if ([string]::IsNullOrWhiteSpace(\$commandId)) {
                                throw 'SSM Command ID was not returned.'
                            }

                            Write-Host "SSM Command ID: \$commandId"

                            \$status = 'Pending'

                            for (\$i = 1; \$i -le 60; \$i++) {

                                Start-Sleep -Seconds 5

                                \$invocation = aws ssm get-command-invocation `
                                    --region '${env.AWS_REGION}' `
                                    --command-id \$commandId `
                                    --instance-id '${env.WORKLOAD_INSTANCE_ID}' `
                                    --output json | ConvertFrom-Json

                                \$status = \$invocation.Status

                                Write-Host "SSM Status: \$status"

                                if (
                                    \$status -eq 'Success' -or
                                    \$status -eq 'Failed' -or
                                    \$status -eq 'Cancelled' -or
                                    \$status -eq 'TimedOut'
                                ) {
                                    break
                                }
                            }

                            Write-Host ''
                            Write-Host '========================================'
                            Write-Host 'SSM DEPLOYMENT RESULT'
                            Write-Host '========================================'

                            Write-Host "Command ID : \$commandId"
                            Write-Host "Status     : \$status"

                            \$final = aws ssm get-command-invocation `
                                --region '${env.AWS_REGION}' `
                                --command-id \$commandId `
                                --instance-id '${env.WORKLOAD_INSTANCE_ID}' `
                                --output json | ConvertFrom-Json

                            Write-Host ''
                            Write-Host '---------- STANDARD OUTPUT ----------'

                            if (\$final.StandardOutputContent) {
                                Write-Host \$final.StandardOutputContent
                            }

                            Write-Host ''
                            Write-Host '---------- STANDARD ERROR ----------'

                            if (\$final.StandardErrorContent) {
                                Write-Host \$final.StandardErrorContent
                            }

                            Write-Host ''
                            Write-Host '========================================'

                            if (\$status -ne 'Success') {
                                throw "EC2 deployment failed. SSM status: \$status"
                            }

                            Write-Host 'DEPLOYMENT SUCCESSFUL'
                            Write-Host '========================================'
                        """
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {

                    powershell """
                        \$ErrorActionPreference = 'Stop'

                        Write-Host '========================================'
                        Write-Host 'VERIFYING EC2'
                        Write-Host '========================================'

                        aws ssm describe-instance-information `
                            --region '${env.AWS_REGION}'

                        Write-Host ''
                        Write-Host 'EC2 instance is registered with SSM.'
                        Write-Host 'Deployment verification completed.'
                    """
                }
            }
        }
    }

    post {

        success {
            echo '''
========================================
WIZ MANAGED IDENTITY LAB
DEPLOYMENT SUCCESSFUL
========================================
'''
        }

        failure {
            echo '''
========================================
WIZ MANAGED IDENTITY LAB
DEPLOYMENT FAILED
========================================
Check the failed stage in Console Output.
'''
        }
    }
}