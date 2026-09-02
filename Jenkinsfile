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
                bat "docker build -t %ECR_REPOSITORY%:%IMAGE_TAG% app"
            }
        }

        stage('Authenticate to ECR') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat "aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com"
                }
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'wiz-lab-jenkins-aws']
                ]) {
                    bat "docker tag %ECR_REPOSITORY%:%IMAGE_TAG% %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%"

                    bat "docker push %AWS_ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPOSITORY%:%IMAGE_TAG%"
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

                        def region = env.AWS_REGION
                        def account = env.AWS_ACCOUNT_ID
                        def repository = env.ECR_REPOSITORY
                        def tag = env.IMAGE_TAG
                        def instance = env.WORKLOAD_INSTANCE_ID

                        def registry = "${account}.dkr.ecr.${region}.amazonaws.com"
                        def image = "${registry}/${repository}:${tag}"

                        echo "========================================"
                        echo "WIZ MANAGED IDENTITY LAB"
                        echo "Deployment Information"
                        echo "========================================"
                        echo "AWS Region     : ${region}"
                        echo "AWS Account    : ${account}"
                        echo "ECR Repository : ${repository}"
                        echo "Image Tag      : ${tag}"
                        echo "ECR Image      : ${image}"
                        echo "EC2 Instance   : ${instance}"
                        echo "========================================"

                        echo "Checking Jenkins AWS identity..."

                        bat "aws sts get-caller-identity --region ${region}"

                        echo "Checking SSM managed instance..."

                        bat "aws ssm describe-instance-information --region ${region}"

                        /*
                         * Commands executed ON the EC2 instance
                         */
                        def commands = [
                            "set -e",
                            "echo 'Starting Wiz Managed Identity application deployment'",
                            "echo 'Logging in to Amazon ECR'",
                            "aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${registry}",
                            "echo 'Pulling Docker image ${image}'",
                            "docker pull ${image}",
                            "echo 'Removing existing wiz-lab-app container'",
                            "docker rm -f wiz-lab-app || true",
                            "echo 'Starting new wiz-lab-app container'",
                            "docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=wiz-managed-identity-lab-sensitive-139830186338 ${image}",
                            "echo 'Checking container status'",
                            "docker ps --filter name=wiz-lab-app",
                            "echo 'Deployment completed successfully'"
                        ]

                        /*
                         * Create SSM parameter JSON
                         */
                        def parameters = [
                            commands: commands
                        ]

                        writeFile(
                            file: 'ssm-parameters.json',
                            text: groovy.json.JsonOutput.toJson(parameters)
                        )

                        echo "SSM parameter file created."

                        /*
                         * Send command to EC2
                         */
                        echo "Sending deployment command through SSM..."

                        bat "aws ssm send-command --region ${region} --instance-ids ${instance} --document-name AWS-RunShellScript --comment \"Deploy Wiz managed identity application\" --parameters file://ssm-parameters.json --output json > ssm-command.json"

                        /*
                         * Read CommandId using PowerShell JSON parsing
                         */
                        def commandId = powershell(
                            script: '(Get-Content ssm-command.json -Raw | ConvertFrom-Json).Command.CommandId',
                            returnStdout: true
                        ).trim()

                        if (!commandId) {
                            error("SSM did not return a CommandId.")
                        }

                        echo "SSM Command ID: ${commandId}"

                        /*
                         * Wait for command completion
                         */
                        echo "Waiting for EC2 deployment to complete..."

                        def finalStatus = "Pending"

                        for (int i = 1; i <= 36; i++) {

                            sleep time: 5, unit: 'SECONDS'

                            def status = powershell(
                                script: """
                                (aws ssm get-command-invocation --region ${region} --command-id ${commandId} --instance-id ${instance} --output json | ConvertFrom-Json).Status
                                """,
                                returnStdout: true
                            ).trim()

                            finalStatus = status

                            echo "SSM Status: ${finalStatus}"

                            if (finalStatus in [
                                "Success",
                                "Failed",
                                "Cancelled",
                                "TimedOut",
                                "Cancelling"
                            ]) {
                                break
                            }
                        }

                        /*
                         * Retrieve final SSM output
                         */
                        def resultJson = powershell(
                            script: """
                            aws ssm get-command-invocation --region ${region} --command-id ${commandId} --instance-id ${instance} --output json
                            """,
                            returnStdout: true
                        ).trim()

                        def result = new groovy.json.JsonSlurperClassic().parseText(resultJson)

                        echo "========================================"
                        echo "SSM DEPLOYMENT RESULT"
                        echo "========================================"

                        echo "Command ID : ${commandId}"
                        echo "Status     : ${result.Status}"
                        echo "Response   : ${result.ResponseCode}"

                        echo "----- Standard Output -----"
                        echo "${result.StandardOutputContent}"

                        echo "----- Standard Error -----"
                        echo "${result.StandardErrorContent}"

                        echo "========================================"

                        if (result.Status != "Success") {
                            error("EC2 deployment failed. SSM status: ${result.Status}")
                        }

                        echo "========================================"
                        echo "DEPLOYMENT SUCCESSFUL"
                        echo "========================================"
                    }
                }
            }
        }
    }
}