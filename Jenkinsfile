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

                    script {

                        echo '========================================'
                        echo 'Starting SSM Deployment'
                        echo '========================================'

                        echo "AWS Region     : ${env.AWS_REGION}"
                        echo "AWS Account    : ${env.AWS_ACCOUNT_ID}"
                        echo "ECR Repository : ${env.ECR_REPOSITORY}"
                        echo "Image Tag      : ${env.IMAGE_TAG}"
                        echo "EC2 Instance   : ${env.WORKLOAD_INSTANCE_ID}"

                        /*
                         * Verify Jenkins AWS identity
                         */
                        echo 'Checking AWS identity...'

                        bat '''
                            aws sts get-caller-identity
                        '''

                        /*
                         * Verify SSM instance
                         */
                        echo 'Checking SSM managed instance...'

                        bat '''
                            aws ssm describe-instance-information --region %AWS_REGION%
                        '''

                        /*
                         * Create the ECR image URL
                         */
                        def registry = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                        def image = "${registry}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"

                        echo "Image to deploy: ${image}"

                        /*
                         * Commands executed on EC2
                         */
                        def ssmJson = """
{
    "commands": [
        "set -e",
        "echo Starting Wiz Managed Identity application deployment",
        "echo Logging in to Amazon ECR",
        "aws ecr get-login-password --region ${env.AWS_REGION} | docker login --username AWS --password-stdin ${registry}",
        "echo Pulling image ${image}",
        "docker pull ${image}",
        "echo Removing old container if present",
        "docker rm -f wiz-lab-app || true",
        "echo Starting new container",
        "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=wiz-managed-identity-lab-sensitive-139830186338 ${image}",
        "echo Checking running container",
        "docker ps --filter name=wiz-lab-app",
        "echo Deployment completed successfully"
    ]
}
"""

                        /*
                         * Write JSON file.
                         */
                        writeFile(
                            file: 'ssm-parameters.json',
                            text: ssmJson.trim()
                        )

                        echo 'SSM parameter file created.'

                        /*
                         * Send command to EC2.
                         *
                         * Output is saved to a JSON file.
                         */
                        echo 'Sending SSM command...'

                        bat """
                            aws ssm send-command ^
                            --region ${env.AWS_REGION} ^
                            --instance-ids ${env.WORKLOAD_INSTANCE_ID} ^
                            --document-name AWS-RunShellScript ^
                            --comment "Deploy Wiz managed identity application" ^
                            --parameters file://ssm-parameters.json ^
                            --output json > ssm-command.json
                        """

                        /*
                         * Extract CommandId using PowerShell.
                         *
                         * IMPORTANT:
                         * No JsonSlurper / Groovy JSON parser is used.
                         */
                        def commandId = powershell(
                            script: '''
                                $json = Get-Content "ssm-command.json" -Raw | ConvertFrom-Json
                                $json.Command.CommandId
                            ''',
                            returnStdout: true
                        ).trim()

                        if (commandId == '') {
                            error('Unable to obtain SSM CommandId.')
                        }

                        echo "SSM Command ID: ${commandId}"

                        /*
                         * Wait for SSM command.
                         */
                        echo 'Waiting for SSM deployment...'

                        def status = 'Pending'

                        for (int i = 0; i < 36; i++) {

                            sleep time: 5, unit: 'SECONDS'

                            status = powershell(
                                script: """
                                    \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                    \$result.Status
                                """,
                                returnStdout: true
                            ).trim()

                            echo "SSM Status: ${status}"

                            if (
                                status == 'Success' ||
                                status == 'Failed' ||
                                status == 'Cancelled' ||
                                status == 'TimedOut' ||
                                status == 'Cancelling'
                            ) {
                                break
                            }
                        }

                        /*
                         * Get Standard Output.
                         */
                        def standardOutput = powershell(
                            script: """
                                \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                \$result.StandardOutputContent
                            """,
                            returnStdout: true
                        ).trim()

                        /*
                         * Get Standard Error.
                         */
                        def standardError = powershell(
                            script: """
                                \$result = aws ssm get-command-invocation --region ${env.AWS_REGION} --command-id ${commandId} --instance-id ${env.WORKLOAD_INSTANCE_ID} --output json | ConvertFrom-Json
                                \$result.StandardErrorContent
                            """,
                            returnStdout: true
                        ).trim()

                        /*
                         * Display deployment result.
                         */
                        echo '========================================'
                        echo 'SSM DEPLOYMENT RESULT'
                        echo '========================================'

                        echo "Command ID : ${commandId}"
                        echo "Status     : ${status}"

                        echo '----- Standard Output -----'

                        if (standardOutput != '') {
                            echo standardOutput
                        } else {
                            echo 'No standard output returned.'
                        }

                        echo '----- Standard Error -----'

                        if (standardError != '') {
                            echo standardError
                        } else {
                            echo 'No standard error returned.'
                        }

                        echo '========================================'

                        /*
                         * Fail Jenkins only if EC2 deployment actually failed.
                         */
                        if (status != 'Success') {
                            error("SSM deployment failed. Final status: ${status}")
                        }

                        echo '========================================'
                        echo 'DEPLOYMENT SUCCESSFUL'
                        echo '========================================'
                    }
                }
            }
        }
    }

    post {

        success {
            echo 'Wiz Managed Identity Lab pipeline completed successfully.'
        }

        failure {
            echo 'Wiz Managed Identity Lab pipeline failed.'
            echo 'Check the stage output above for the exact failure.'
        }
    }
}