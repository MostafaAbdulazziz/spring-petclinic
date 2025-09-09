pipeline {
    agent none // Agent will be defined per stage

    // The 'tools' block has been REMOVED as the Docker image contains Maven and Java.

    environment {
        // --- Configuration ---
        DOCKERHUB_USERNAME      = "mostafaabdelazziz"
        DOCKER_IMAGE_NAME       = "${DOCKERHUB_USERNAME}/petclinic"
        EC2_STAGING_HOST        = "ec2-user@ec2-13-48-136-47.eu-north-1.compute.amazonaws.com"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
    }

    stages {
        stage('Build and Analyze in Parallel') {
            parallel {
                stage('Build and Test') {
                    agent {
                        docker {
                            image 'maven:3.9.6-eclipse-temurin-17'
                            args '-v /var/lib/jenkins/.m2:/root/.m2'
                        }
                    }
                    steps {
                        sh "mvn clean install"
                        stash name: 'jar-file', includes: 'target/*.jar'
                    }
                }
                stage('SonarQube Analysis') {
                    agent {
                        docker {
                            image 'maven:3.9.6-eclipse-temurin-17'
                            args '-v /var/lib/jenkins/.m2:/root/.m2'
                        }
                    }
                    steps {
                        withCredentials([string(credentialsId: '9091', variable: 'SONAR_TOKEN')]) {
                            // This name 'SonarQubeServer' MUST match the one you configure in Manage Jenkins
                            withSonarQubeEnv('SonarQubeServer') {
                                sh "mvn sonar:sonar -Dsonar.login=${SONAR_TOKEN}"
                            }
                        }
                    }
                }
            }
        }

        // ... rest of your pipeline stages (Build & Push, Install Docker, Deploy) remain the same ...

        stage('Build & Push Docker Image') {
            agent any
            steps {
                script {
                    unstash 'jar-file'
                    docker.withRegistry("https://index.docker.io/v1/", 'dockerhub_token') {
                        def customImage = docker.build(DOCKER_IMAGE_NAME, ".")
                        customImage.push("${env.BUILD_NUMBER}")
                        customImage.push("latest")
                    }
                }
            }
        }

        stage('Install Docker on Staging Host') {
            agent any
            steps {
                sshagent(['ec2-app-deployer-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                            set -e
                            STAGING_USER=\$(echo "${EC2_STAGING_HOST}" | cut -d"@" -f1)

                            if ! command -v docker &> /dev/null; then
                                echo "Docker not found. Installing..."
                                sudo yum update -y
                                sudo yum install -y docker
                                sudo systemctl start docker
                                sudo systemctl enable docker
                                sudo usermod -aG docker \$STAGING_USER
                                echo "Docker installed successfully."
                            else
                                echo "Docker is already installed."
                            fi

                            if ! command -v docker-compose &> /dev/null; then
                                echo "Docker Compose not found. Installing..."
                                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
                                sudo chmod +x /usr/local/bin/docker-compose
                                echo "Docker Compose installed successfully."
                            else
                                echo "Docker Compose is already installed."
                            fi
                        '
                    """
                }
            }
        }
        
        stage('Deploy to Staging') {
            agent any
            steps {
                withCredentials([string(credentialsId: 'petclinic_db_password', variable: 'DB_PASS_SECRET')]) {
                    sshagent(['ec2-app-deployer-key']) {
                        sh """
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_STAGING_HOST}:~/
                            ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                                export TAG=${env.BUILD_NUMBER}
                                export DB_NAME=${DB_NAME}
                                export DB_USER=${DB_USER}
                                export DB_PASS=${DB_PASS_SECRET}
                                export MYSQL_ROOT_PASSWORD=${DB_PASS_SECRET}
                                
                                docker-compose pull app
                                docker-compose up -d
                            '
                        """
                    }
                }
            }
        }
    }
}

