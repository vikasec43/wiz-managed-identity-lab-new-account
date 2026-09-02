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
                        echo "Deployment Information"
                        echo "========================================"
                        echo "Region   : ${region}"
                        echo "Account  : ${account}"
                        echo "Image    : ${image}"
                        echo "Instance : ${instance}"
                        echo "========================================"

                        bat "aws sts get-caller-identity --region ${region}"

                        bat "aws ssm describe-instance-information --region ${region}"

                        writeFile(
                            file: 'ssm-parameters.json',
                            text: """{"commands":["set -e","echo Starting deployment","aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${registry}","docker pull ${image}","docker rm -f wiz-lab-app || true","docker run -d --restart unless-stopped --name wiz-lab-app -p 8080:8080 -e SENSITIVE_BUCKET=wiz-managed-identity-lab-sensitive-139830186338 ${image}","docker ps --filter name=wiz-lab-app","echo Deployment completed"]}"""
                        )

                        echo "Sending deployment command through SSM..."

                        bat "aws ssm send-command --region ${region} --instance-ids ${instance} --document-name AWS-RunShellScript --comment \"Deploy Wiz managed identity application\" --parameters file://ssm-parameters.json --output json > ssm-command.json"

                        def commandId = bat(
                            script: '@for /f "tokens=2 delims=:, " %A in (\'findstr /C:"CommandId" ssm-command.json\') do @echo %A',
                            returnStdout: true
                        ).trim()

                        commandId = commandId.replace('"', '')

                        if (!commandId) {
                            error("Could not obtain SSM Command ID.")
                        }

                        echo "SSM Command ID: ${commandId}"

                        echo "Waiting for SSM deployment..."

                        bat "timeout /t 10 /nobreak"

                        def status = "InProgress"

                        for (int i = 1; i <= 30; i++) {

                            bat "aws ssm get-command-invocation --region ${region} --command-id ${commandId} --instance-id ${instance} --output json > ssm-result.json"

                            def resultText = readFile('ssm-result.json')

                            echo "SSM response received."

                            if (resultText.contains('"Status": "Success"')) {
                                status = "Success"
                                break
                            }

                            if (resultText.contains('"Status": "Failed"')) {
                                status = "Failed"
                                break
                            }

                            if (resultText.contains('"Status": "Cancelled"')) {
                                status = "Cancelled"
                                break
                            }

                            if (resultText.contains('"Status": "TimedOut"')) {
                                status = "TimedOut"
                                break
                            }

                            bat "timeout /t 5 /nobreak"
                        }

                        echo "========================================"
                        echo "Final SSM Status: ${status}"
                        echo "========================================"

                        echo readFile('ssm-result.json')

                        if (status != "Success") {
                            error("SSM deployment failed. Final status: ${status}")
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