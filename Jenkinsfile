pipeline {
    agent none

    environment {
        EC2_STAGING_HOST        = "ubuntu@ec2-13-48-68-86.eu-north-1.compute.amazonaws.com" // Ubuntu EC2 instance
        NEXUS_REGISTRY          = "ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        STAGING_USER            = "ubuntu" // Explicitly set for Ubuntu
    }

    stages {
        stage('Build and Test') {
            agent any
            steps {
                sh "mvn clean install"
                stash name: 'jar-file', includes: 'target/*.jar'
            }
        }
        
        stage('SonarQube Analysis') {
            agent any
            steps {
                withCredentials([string(credentialsId: '9091', variable: 'SONAR_TOKEN')]) {
                    withSonarQubeEnv('SonarQubeServer') {
                        sh "mvn sonar:sonar -Dsonar.login=${SONAR_TOKEN}"
                    }
                }
            }
        }
        
        stage('Build & Push Docker Image') {
            agent any
            steps {
                withCredentials([
                    string(credentialsId: 'nexus_docker_username', variable: 'NEXUS_USERNAME'),
                    string(credentialsId: 'nexus_docker_password', variable: 'NEXUS_PASSWORD')
                ]) {
                    unstash 'jar-file'
                    sh """
                        docker build -t spring-petclinic:${BUILD_NUMBER} .
                        docker tag spring-petclinic:${BUILD_NUMBER} ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:${BUILD_NUMBER}
                        docker tag spring-petclinic:${BUILD_NUMBER} ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:latest
                        echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin
                        docker push ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:${BUILD_NUMBER}
                        docker push ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:latest
                    """
                }
            }
        }

        stage('Install Docker on Staging Host') {
            agent any
            steps {
                sshagent(['ec2-app-deployer-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} 
                            set -e
                            # --- Install Docker (Ubuntu) ---
                            if ! command -v docker &> /dev/null; then
                                echo "Docker not found. Installing..."
                                sudo apt-get update -y
                                sudo apt-get install -y docker.io
                                sudo systemctl start docker
                                sudo systemctl enable docker
                                sudo usermod -aG docker ubuntu
                                echo "Docker installed successfully."
                            else
                                echo "Docker is already installed."
                            fi

                            # --- Install Docker Compose (Ubuntu) ---
                            if ! command -v docker-compose &> /dev/null; then
                                echo "Docker Compose not found. Installing..."
                                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                                sudo chmod +x /usr/local/bin/docker-compose
                                echo "Docker Compose installed successfully."
                            else
                                echo "Docker Compose is already installed."
                            fi

                            # --- Configure Docker for insecure registry ---
                            if ! grep -q "${NEXUS_REGISTRY}" /etc/docker/daemon.json 2>/dev/null; then
                                echo "Configuring Docker daemon for insecure registry..."
                                sudo mkdir -p /etc/docker
                                echo '{"insecure-registries":["${NEXUS_REGISTRY}"]}' | sudo tee /etc/docker/daemon.json
                                sudo systemctl restart docker
                                echo "Docker daemon configured for insecure registry."
                            fi
                        '
                    """
                }
            }
        }
        
        stage('Deploy to Staging') {
            agent any
            steps {
                withCredentials([
                    string(credentialsId: 'petclinic_db_password', variable: 'DB_PASS_SECRET'),
                    string(credentialsId: 'nexus_docker_username', variable: 'NEXUS_USERNAME'),
                    string(credentialsId: 'nexus_docker_password', variable: 'NEXUS_PASSWORD')
                ]) {
                    sshagent(['ec2-app-deployer-key']) {
                        sh """
                            # Copy the compose file to the EC2 Ubuntu instance
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_STAGING_HOST}:~/

                            # SSH into the Ubuntu instance to deploy containers
                            ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                                # Export variables for docker-compose
                                export BUILD_NUMBER=${BUILD_NUMBER}
                                export DB_NAME=${DB_NAME}
                                export DB_USER=${DB_USER}
                                export DB_PASS=${DB_PASS_SECRET}
                                export MYSQL_ROOT_PASSWORD=${DB_PASS_SECRET}
                                export NEXUS_REGISTRY=${NEXUS_REGISTRY}

                                # Login to Nexus registry on staging server
                                echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin

                                # Stop existing containers
                                docker-compose down || true

                                # Pull the latest images
                                docker-compose pull

                                # Start services
                                docker-compose -f docker-compose-prod.yml up -d

                                # Wait for services to start
                                sleep 30

                                # Check service status
                                docker-compose ps

                                # Check application health
                                echo "Waiting for application to start..."
                                for i in {1..30}; do
                                    if curl -f http://localhost:8080/actuator/health 2>/dev/null; then
                                        echo "Application is healthy!"
                                        break
                                    fi
                                    echo "Attempt $i: Application not ready yet..."
                                    sleep 10
                                done
                            '
                        """
                    }
                }
            }
        }
    }
}