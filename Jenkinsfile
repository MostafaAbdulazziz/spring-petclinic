pipeline {
    agent none

    environment {
        EC2_STAGING_HOST        = "ubuntu@ec2-13-48-68-86.eu-north-1.compute.amazonaws.com"
        NEXUS_REGISTRY          = "ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        STAGING_USER            = "ubuntu"
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
                        ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                            set -e
                            echo "Setting up Docker on Ubuntu..."
                            
                            # --- Install Docker (Ubuntu) ---
                            if ! command -v docker &> /dev/null; then
                                echo "Docker not found. Installing..."
                                sudo apt-get update -y
                                sudo apt-get install -y docker.io
                                sudo systemctl start docker
                                sudo systemctl enable docker
                                sudo usermod -aG docker ${STAGING_USER}
                                echo "Docker installed successfully."
                            else
                                echo "Docker is already installed."
                                docker --version
                            fi

                            # --- Install Docker Compose (Ubuntu) ---
                            if ! command -v docker-compose &> /dev/null; then
                                echo "Docker Compose not found. Installing..."
                                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
                                sudo chmod +x /usr/local/bin/docker-compose
                                sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
                                echo "Docker Compose installed successfully."
                            else
                                echo "Docker Compose is already installed."
                                docker-compose --version
                            fi

                            # --- Configure Docker for insecure registry ---
                            echo "Configuring Docker daemon for insecure registry..."
                            sudo mkdir -p /etc/docker
                            
                            # Create daemon.json with proper escaping
                            echo "{\"insecure-registries\":[\"${NEXUS_REGISTRY}\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
                            
                            # Restart Docker service
                            sudo systemctl restart docker
                            
                            # Wait for Docker to restart
                            sleep 10
                            
                            # Verify Docker is running
                            sudo systemctl status docker --no-pager
                            echo "Docker daemon configured for insecure registry."
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
                                set -e
                                echo "Starting deployment process..."
                                
                                # Export variables for docker-compose
                                export BUILD_NUMBER=${BUILD_NUMBER}
                                export DB_NAME=${DB_NAME}
                                export DB_USER=${DB_USER}
                                export DB_PASS=${DB_PASS_SECRET}
                                export MYSQL_ROOT_PASSWORD=${DB_PASS_SECRET}
                                export NEXUS_REGISTRY=${NEXUS_REGISTRY}
                                
                                echo "Environment variables set for deployment."

                                # Login to Nexus registry on staging server
                                echo "Logging into Nexus registry..."
                                echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin

                                # Stop existing containers (use correct docker-compose file)
                                echo "Stopping existing containers..."
                                docker-compose down --remove-orphans || true

                                # Pull the latest images
                                echo "Pulling latest images..."
                                docker-compose pull

                                # Start services (use the correct compose file name)
                                echo "Starting services..."
                                docker-compose up -d

                                # Wait for services to start
                                echo "Waiting for services to initialize..."
                                sleep 45

                                # Check service status
                                echo "=== Service Status ==="
                                docker-compose ps
                                echo ""
                                docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"

                                # Check application health with better error handling
                                echo "=== Application Health Check ==="
                                for i in {1..30}; do
                                    echo "Health check attempt \$i/30..."
                                    if curl -f -s --connect-timeout 5 http://localhost:8080/actuator/health >/dev/null 2>&1; then
                                        echo "✅ Application health endpoint is responding!"
                                        curl -s http://localhost:8080/actuator/health || echo "Health endpoint accessible"
                                        break
                                    elif curl -f -s --connect-timeout 5 http://localhost:8080 >/dev/null 2>&1; then
                                        echo "✅ Application root endpoint is responding!"
                                        break
                                    else
                                        if [ \$i -eq 30 ]; then
                                            echo "❌ Application failed to respond after 30 attempts"
                                            echo "=== Container Logs ==="
                                            docker-compose logs --tail=50 petclinic || echo "Could not retrieve logs"
                                            echo "=== Container Status ==="
                                            docker-compose ps
                                        else
                                            echo "⏳ Application not ready yet, waiting 10 seconds..."
                                            sleep 10
                                        fi
                                    fi
                                done
                                
                                echo "=== Final Deployment Status ==="
                                docker-compose ps
                                echo ""
                                echo "🎉 Deployment process completed!"
                                echo "Application should be accessible at: http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo \"PUBLIC_IP\"):8080"
                            '
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "Pipeline execution completed."
        }
        success {
            echo "🎉 Pipeline executed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check the logs above for details."
        }
    }
}