pipeline {
    agent any

    environment {
        AWS_REGION              = 'us-east-1'
        AWS_ACCOUNT_ID          = '139830186338'
        ECR_REPOSITORY          = 'wiz-managed-identity-app'
        IMAGE_TAG               = "${BUILD_NUMBER}"
        WORKLOAD_INSTANCE_ID    = 'i-02e8dd862397203ad'
        SENSITIVE_BUCKET        = 'wiz-managed-identity-lab-sensitive-139830186338'
        JENKINS_AWS_CREDENTIAL  = 'wiz-lab-jenkins-aws'
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

                        if %ERRORLEVEL% NEQ 0 exit /b 1
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

                    docker build ^
                        -t %ECR_REPOSITORY%:%IMAGE_TAG% ^
                        app

                    if %ERRORLEVEL% NEQ 0 exit /b 1
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

                        aws ecr get-login-password ^
                            --region %AWS_REGION% ^
                            | docker login ^
                            --username AWS ^
                            --password-stdin ^
                            %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com

                        if %ERRORLEVEL% NEQ 0 exit /b 1
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
                        echo TAGGING IMAGE
                        echo ========================================

                        docker tag ^
                            %ECR_REPOSITORY%:%IMAGE_TAG% ^
                            %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%

                        if %ERRORLEVEL% NEQ 0 exit /b 1

                        echo ========================================
                        echo PUSHING IMAGE TO ECR
                        echo ========================================

                        docker push ^
                            %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%

                        if %ERRORLEVEL% NEQ 0 exit /b 1
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
                         * Commands executed on EC2.
                         *
                         * EC2 is Amazon Linux.
                         * SSM executes the commands as root.
                         */

                        def commands = [
                            "set -e",
                            "echo Starting deployment",
                            "echo Checking Docker",
                            "if ! command -v docker >/dev/null 2>&1; then dnf install -y docker; fi",
                            "systemctl enable docker",
                            "systemctl start docker",
                            "docker --version",
                            "echo Logging into ECR",
                            "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${registry}",
                            "echo Pulling image",
                            "docker pull ${image}",
                            "echo Removing previous container",
                            "docker rm -f wiz-lab-app || true",
                            "echo Starting application",
                            "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=${env.SENSITIVE_BUCKET} ${image}",
                            "sleep 5",
                            "echo Checking container",
                            "docker ps --filter name=wiz-lab-app",
                            "echo Deployment completed successfully"
                        ]

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
                         * Send SSM command.
                         *
                         * IMPORTANT:
                         * We only extract CommandId.
                         * We do NOT pipe the complete response
                         * through ConvertFrom-Json in the polling loop.
                         */

                        powershell(
                            script: """
                                \$ErrorActionPreference = 'Stop'

                                \$response = aws ssm send-command `
                                    --region '${env.AWS_REGION}' `
                                    --instance-ids '${env.WORKLOAD_INSTANCE_ID}' `
                                    --document-name 'AWS-RunShellScript' `
                                    --comment 'Deploy Wiz Managed Identity Lab application' `
                                    --parameters file://ssm-parameters.json `
                                    --query 'Command.CommandId' `
                                    --output text

                                if (\$LASTEXITCODE -ne 0) {
                                    throw 'Failed to send SSM command.'
                                }

                                \$response = \$response.Trim()

                                if ([string]::IsNullOrWhiteSpace(\$response)) {
                                    throw 'SSM Command ID was not returned.'
                                }

                                Set-Content `
                                    -Path 'ssm-command-id.txt' `
                                    -Value \$response `
                                    -Encoding ascii

                                Write-Host "SSM Command ID: \$response"
                            """
                        )

                        def commandId = readFile(
                            file: 'ssm-command-id.txt'
                        ).trim()

                        echo "SSM Command ID: ${commandId}"

                        /*
                         * Wait for SSM execution.
                         *
                         * AWS CLI waiter handles polling.
                         * No JSON parsing is required here.
                         */

                        powershell(
                            script: """
                                \$ErrorActionPreference = 'Stop'

                                Write-Host 'Waiting for SSM command to complete...'

                                aws ssm wait command-executed `
                                    --region '${env.AWS_REGION}' `
                                    --command-id '${commandId}' `
                                    --instance-id '${env.WORKLOAD_INSTANCE_ID}'

                                if (\$LASTEXITCODE -ne 0) {
                                    throw 'SSM command did not complete successfully.'
                                }

                                Write-Host 'SSM command completed successfully.'
                            """
                        )

                        /*
                         * Get final status.
                         *
                         * Use --query to return only the status.
                         */

                        def finalStatus = powershell(
                            script: """
                                \$ErrorActionPreference = 'Stop'

                                aws ssm get-command-invocation `
                                    --region '${env.AWS_REGION}' `
                                    --command-id '${commandId}' `
                                    --instance-id '${env.WORKLOAD_INSTANCE_ID}' `
                                    --query 'Status' `
                                    --output text
                            """,
                            returnStdout: true
                        ).trim()

                        echo "Final SSM Status: ${finalStatus}"

                        if (finalStatus != 'Success') {
                            error(
                                "EC2 deployment failed. SSM status: ${finalStatus}"
                            )
                        }

                        /*
                         * Retrieve standard output separately.
                         *
                         * --output text prevents JSON parsing.
                         */

                        echo "========================================"
                        echo "SSM DEPLOYMENT OUTPUT"
                        echo "========================================"

                        powershell(
                            script: """
                                aws ssm get-command-invocation `
                                    --region '${env.AWS_REGION}' `
                                    --command-id '${commandId}' `
                                    --instance-id '${env.WORKLOAD_INSTANCE_ID}' `
                                    --query 'StandardOutputContent' `
                                    --output text
                            """
                        )

                        echo "========================================"
                        echo "EC2 DEPLOYMENT SUCCESSFUL"
                        echo "========================================"
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
                        Write-Host 'VERIFYING EC2 SSM STATUS'
                        Write-Host '========================================'

                        aws ssm describe-instance-information `
                            --region '${env.AWS_REGION}' `
                            --query 'InstanceInformationList[?InstanceId==\\`${env.WORKLOAD_INSTANCE_ID}\\`].[InstanceId,PingStatus,PlatformName]' `
                            --output table

                        if (\$LASTEXITCODE -ne 0) {
                            throw 'Unable to verify EC2 SSM status.'
                        }

                        Write-Host ''
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
Review the failed stage in Console Output.
========================================
'''
        }
    }
}