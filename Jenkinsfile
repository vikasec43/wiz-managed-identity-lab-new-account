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
                    script {

                        def registry =
                            "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                        def image =
                            "${registry}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                        echo "========================================"
                        echo "Deploying Application to EC2"
                        echo "========================================"
                        echo "EC2 Instance : ${env.WORKLOAD_INSTANCE_ID}"
                        echo "Docker Image : ${image}"

                        /*
                         * Create SSM command parameters as JSON.
                         *
                         * This avoids Windows CMD quoting problems.
                         */
                        def ssmParameters = """
{
    "commands": [
        "set -e",
        "echo Starting deployment",
        "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${registry}",
        "docker pull ${image}",
        "docker rm -f wiz-lab-app || true",
        "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=${env.SENSITIVE_BUCKET} ${image}",
        "docker ps --filter name=wiz-lab-app",
        "echo Deployment completed"
    ]
}
"""

                        writeFile(
                            file: 'ssm-parameters.json',
                            text: ssmParameters.trim()
                        )

                        echo "SSM parameter file created."

                        /*
                         * Send command to EC2 through SSM.
                         */
                        bat """
                            aws ssm send-command ^
                            --region ${env.AWS_REGION} ^
                            --instance-ids ${env.WORKLOAD_INSTANCE_ID} ^
                            --document-name AWS-RunShellScript ^
                            --comment "Deploy Wiz Managed Identity Lab" ^
                            --parameters file://ssm-parameters.json ^
                            --output json > ssm-command.json
                        """

                        /*
                         * Extract SSM Command ID.
                         */
                        def commandId = powershell(
                            script: '''
                                $json = Get-Content "ssm-command.json" -Raw | ConvertFrom-Json
                                $json.Command.CommandId
                            ''',
                            returnStdout: true
                        ).trim()

                        if (!commandId) {
                            error("Unable to obtain SSM Command ID.")
                        }

                        echo "SSM Command ID: ${commandId}"

                        /*
                         * Wait for SSM command to complete.
                         */
                        def status = "Pending"

                        for (int i = 0; i < 36; i++) {

                            sleep(
                                time: 5,
                                unit: 'SECONDS'
                            )

                            status = powershell(
                                script: """
                                    \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                    \$result.Status
                                """,
                                returnStdout: true
                            ).trim()

                            echo "SSM Status: ${status}"

                            if (
                                status == "Success" ||
                                status == "Failed" ||
                                status == "Cancelled" ||
                                status == "TimedOut"
                            ) {
                                break
                            }
                        }

                        /*
                         * Get SSM command output.
                         */
                        def output = powershell(
                            script: """
                                \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                \$result.StandardOutputContent
                            """,
                            returnStdout: true
                        ).trim()

                        def errorOutput = powershell(
                            script: """
                                \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                \$result.StandardErrorContent
                            """,
                            returnStdout: true
                        ).trim()

                        echo "========================================"
                        echo "SSM DEPLOYMENT RESULT"
                        echo "========================================"

                        echo "Command ID : ${commandId}"
                        echo "Status     : ${status}"

                        echo "---------- Standard Output ----------"

                        if (output) {
                            echo output
                        }

                        echo "---------- Standard Error ----------"

                        if (errorOutput) {
                            echo errorOutput
                        }

                        echo "========================================"

                        if (status != "Success") {
                            error(
                                "EC2 deployment failed. SSM status: ${status}"
                            )
                        }

                        echo "EC2 deployment completed successfully."
                    }
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