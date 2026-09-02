pipeline {
    agent any

    environment {
        AWS_REGION             = 'us-east-1'
        AWS_ACCOUNT_ID         = '139830186338'
        ECR_REPOSITORY         = 'wiz-managed-identity-app'
        IMAGE_TAG              = "${BUILD_NUMBER}"
        WORKLOAD_INSTANCE_ID   = 'i-02e8dd862397203ad'
        SENSITIVE_BUCKET       = 'wiz-managed-identity-lab-sensitive-139830186338'
        JENKINS_AWS_CREDENTIAL = 'wiz-lab-jenkins-aws'
    }

    stages {

        /*
         * ============================================================
         * 1. CHECKOUT SOURCE CODE
         * ============================================================
         */
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /*
         * ============================================================
         * 2. VERIFY JENKINS AWS IDENTITY
         * ============================================================
         */
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

        /*
         * ============================================================
         * 3. BUILD DOCKER IMAGE
         * ============================================================
         */
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

        /*
         * ============================================================
         * 4. LOGIN TO AMAZON ECR
         * ============================================================
         */
        stage('Authenticate to ECR') {
            steps {

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {

                    bat '''
                        echo ========================================
                        echo AUTHENTICATING TO AMAZON ECR
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

        /*
         * ============================================================
         * 5. TAG AND PUSH IMAGE TO ECR
         * ============================================================
         */
        stage('Push Image to ECR') {
            steps {

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {

                    bat '''
                        echo ========================================
                        echo TAGGING DOCKER IMAGE
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

        /*
         * ============================================================
         * 6. DEPLOY APPLICATION TO EC2 USING SSM
         * ============================================================
         */
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
                        echo "AWS Account : ${env.AWS_ACCOUNT_ID}"
                        echo "Region      : ${env.AWS_REGION}"
                        echo "EC2         : ${env.WORKLOAD_INSTANCE_ID}"
                        echo "Image       : ${image}"
                        echo "S3 Bucket   : ${env.SENSITIVE_BUCKET}"
                        echo "========================================"

                        /*
                         * Commands executed on EC2.
                         *
                         * EC2 is Amazon Linux.
                         * SSM executes these commands with
                         * sufficient privileges to manage Docker.
                         */

                        def commands = [
                            "set -e",

                            "echo Starting deployment",

                            "echo Checking Docker",

                            "if ! command -v docker >/dev/null 2>&1; then dnf install -y docker; fi",

                            "systemctl enable docker",

                            "systemctl start docker",

                            "docker --version",

                            "echo Logging into Amazon ECR",

                            "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${registry}",

                            "echo Pulling application image",

                            "docker pull ${image}",

                            "echo Removing previous application container",

                            "docker rm -f wiz-lab-app || true",

                            "echo Starting application container",

                            "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=${env.SENSITIVE_BUCKET} ${image}",

                            "echo Waiting for application startup",

                            "sleep 5",

                            "echo Checking application container",

                            "docker ps --filter name=wiz-lab-app",

                            "echo Deployment completed successfully"
                        ]

                        /*
                         * Convert command list into JSON.
                         */
                        def jsonCommands =
                            groovy.json.JsonOutput.toJson([
                                commands: commands
                            ])

                        /*
                         * Write SSM parameters to file.
                         *
                         * This avoids Windows CMD quoting problems.
                         */
                        writeFile(
                            file: 'ssm-parameters.json',
                            text: jsonCommands
                        )

                        echo "SSM parameter file created."

                        /*
                         * ------------------------------------------------
                         * SEND SSM COMMAND
                         * ------------------------------------------------
                         */

                        powershell(
                            script: """
                                \$ErrorActionPreference = 'Stop'

                                Write-Host 'Sending SSM deployment command...'

                                \$commandId = aws ssm send-command `
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

                                \$commandId = \$commandId.Trim()

                                if ([string]::IsNullOrWhiteSpace(\$commandId)) {
                                    throw 'SSM Command ID was not returned.'
                                }

                                Set-Content `
                                    -Path 'ssm-command-id.txt' `
                                    -Value \$commandId `
                                    -Encoding ascii

                                Write-Host "SSM Command ID: \$commandId"
                            """
                        )

                        def commandId =
                            readFile(
                                file: 'ssm-command-id.txt'
                            ).trim()

                        echo "SSM Command ID: ${commandId}"

                        /*
                         * ------------------------------------------------
                         * WAIT FOR SSM COMMAND
                         * ------------------------------------------------
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

                                Write-Host 'SSM command completed.'
                            """
                        )

                        /*
                         * ------------------------------------------------
                         * CHECK FINAL SSM STATUS
                         * ------------------------------------------------
                         */

                        def finalStatus =
                            powershell(
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

                            /*
                             * Retrieve error output only when needed.
                             */
                            powershell(
                                script: """
                                    aws ssm get-command-invocation `
                                        --region '${env.AWS_REGION}' `
                                        --command-id '${commandId}' `
                                        --instance-id '${env.WORKLOAD_INSTANCE_ID}' `
                                        --query 'StandardErrorContent' `
                                        --output text
                                """
                            )

                            error(
                                "EC2 deployment failed. SSM status: ${finalStatus}"
                            )
                        }

                        /*
                         * ------------------------------------------------
                         * SHOW DEPLOYMENT OUTPUT
                         * ------------------------------------------------
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

        /*
         * ============================================================
         * 7. FINAL VERIFICATION
         * ============================================================
         *
         * IMPORTANT:
         * No JMESPath filtering is used here.
         * This avoids the Windows escaping problem that caused
         * the previous build to fail.
         * ============================================================
         */
        stage('Verify Deployment') {

            steps {

                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: "${JENKINS_AWS_CREDENTIAL}"]
                ]) {

                    powershell(
                        script: """
                            \$ErrorActionPreference = 'Stop'

                            Write-Host '========================================'
                            Write-Host 'VERIFYING SSM MANAGED INSTANCE'
                            Write-Host '========================================'

                            aws ssm describe-instance-information `
                                --region '${env.AWS_REGION}' `
                                --output table

                            if (\$LASTEXITCODE -ne 0) {
                                throw 'Unable to query SSM managed instances.'
                            }

                            Write-Host ''
                            Write-Host 'EC2 instance is registered with SSM.'
                            Write-Host 'Deployment verification completed.'
                            Write-Host ''
                            Write-Host 'Application should be available on port 8080.'
                            Write-Host '========================================'
                        """
                    )
                }
            }
        }
    }

    /*
     * ================================================================
     * POST ACTIONS
     * ================================================================
     */

    post {

        success {

            echo '''
========================================
WIZ MANAGED IDENTITY LAB
DEPLOYMENT SUCCESSFUL
========================================

Pipeline completed successfully.

GitHub
   |
   v
Jenkins
   |
   v
Docker Build
   |
   v
Amazon ECR
   |
   v
AWS Systems Manager
   |
   v
EC2 Workload
   |
   v
Docker Application
   |
   v
Port 8080

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