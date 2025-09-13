pipeline {
    agent none // Agent will be defined per stage

    // The 'tools' block has been REMOVED as the Docker image contains Maven and Java.

    environment {
        // --- Configuration ---
        DOCKERHUB_USERNAME      = "mostafaabdelazziz"
        DOCKER_IMAGE_NAME       = "${DOCKERHUB_USERNAME}/petclinic"
        EC2_STAGING_HOST        = "ubuntu@ec2-13-48-68-86.eu-north-1.compute.amazonaws.com"
        NEXUS_REGISTRY          = "ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        DB_PASS_SECRET          = "petclinic"
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

        stage('Install Docker on Ubuntu Staging Host') {
            agent any
            steps {
                sshagent(['ec2-app-deployer-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                            set -e
                            STAGING_USER=ubuntu
                            echo "Setting up Docker on Ubuntu for user: \$STAGING_USER"

                            # --- Install Docker on Ubuntu ---
                            if ! command -v docker &> /dev/null; then
                                echo "Docker not found. Installing Docker on Ubuntu..."
                                
                                # Update package index
                                sudo apt-get update -y
                                
                                # Install Docker using apt (simpler method for Ubuntu)
                                sudo apt-get install -y docker.io
                                
                                # Start and enable Docker service
                                sudo systemctl start docker
                                sudo systemctl enable docker
                                
                                # Add user to docker group
                                sudo usermod -aG docker \$STAGING_USER
                                
                                echo "Docker installed successfully on Ubuntu."
                            else
                                echo "Docker is already installed."
                                docker --version
                            fi

                            # --- Install Docker Compose on Ubuntu ---
                            if ! command -v docker-compose &> /dev/null; then
                                echo "Docker Compose not found. Installing..."
                                
                                # Download and install Docker Compose
                                sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
                                
                                # Make it executable
                                sudo chmod +x /usr/local/bin/docker-compose
                                
                                # Create symlink for easier access
                                sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
                                
                                echo "Docker Compose installed successfully."
                            else
                                echo "Docker Compose is already installed."
                                docker-compose --version
                            fi
                            
                            # --- Configure Docker for insecure registry ---
                            echo "Configuring Docker daemon for insecure registry..."
                            sudo mkdir -p /etc/docker
                            
                            # Create daemon.json with insecure registry
                            echo "{\"insecure-registries\":[\"${NEXUS_REGISTRY}\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
                            
                            # Restart Docker service
                            sudo systemctl restart docker
                            
                            # Wait for Docker to fully restart
                            sleep 15
                            
                            # Verify Docker is running
                            sudo systemctl status docker --no-pager -l
                            echo "Docker daemon configured for insecure registry."
                            
                            # Verify installations
                            echo "=== Installation Verification ==="
                            docker --version
                            docker-compose --version
                        '
                    """
                }
            }
        }
        
        stage('Deploy to Ubuntu Staging') {
            agent any
            steps {
                withCredentials([
                    string(credentialsId: 'nexus_docker_username', variable: 'NEXUS_USERNAME'),
                    string(credentialsId: 'nexus_docker_password', variable: 'NEXUS_PASSWORD')
                ]) {
                    sshagent(['ec2-app-deployer-key']) {
                        sh """
                            # Copy the compose file to the Ubuntu EC2 instance
                            echo "Copying docker-compose.yml to Ubuntu staging server..."
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_STAGING_HOST}:~/

                            # SSH into the Ubuntu instance to deploy containers
                            echo "Deploying application on Ubuntu staging server..."
                            ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                                set -e
                                echo "=== Starting Deployment Process ==="
                                
                                # Export variables for docker-compose to read from shell environment
                                export BUILD_NUMBER=${BUILD_NUMBER}
                                export TAG=${BUILD_NUMBER}
                                export DB_NAME=${DB_NAME}
                                export DB_USER=${DB_USER}
                                export DB_PASS=${DB_PASS_SECRET}
                                export MYSQL_ROOT_PASSWORD=${DB_PASS_SECRET}
                                export NEXUS_REGISTRY=${NEXUS_REGISTRY}
                                
                                echo "Environment variables set for deployment:"
                                echo "BUILD_NUMBER: \$BUILD_NUMBER"
                                echo "DB_NAME: \$DB_NAME"
                                echo "DB_USER: \$DB_USER"
                                echo "NEXUS_REGISTRY: \$NEXUS_REGISTRY"
                                
                                # Login to Nexus registry on staging server
                                echo "Logging into Nexus registry..."
                                echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin
                                
                                # Stop and remove existing containers (if any)
                                echo "Stopping existing containers..."
                                docker-compose down --remove-orphans || true
                                
                                # Clean up old images to save space
                                echo "Cleaning up old Docker images..."
                                docker system prune -f || true
                                
                                # Pull the new application image version
                                echo "Pulling latest application images..."
                                docker-compose pull
                                
                                # Bring up both services (database and application)
                                echo "Starting services with docker-compose..."
                                docker-compose up -d
                                
                                # Wait for services to start up
                                echo "Waiting for services to initialize..."
                                sleep 45
                                
                                # Check service status
                                echo "=== Service Status ==="
                                docker-compose ps
                                echo ""
                                docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
                                
                                # Health check for the application
                                echo "=== Application Health Check ==="
                                for i in {1..30}; do
                                    echo "Health check attempt \$i/30..."
                                    if curl -f -s --connect-timeout 5 http://localhost:8080/actuator/health >/dev/null 2>&1; then
                                        echo "✅ Application health endpoint is responding!"
                                        curl -s http://localhost:8080/actuator/health 2>/dev/null | head -3 || echo "Health check passed"
                                        break
                                    elif curl -f -s --connect-timeout 5 http://localhost:8080 >/dev/null 2>&1; then
                                        echo "✅ Application root endpoint is responding!"
                                        break
                                    else
                                        if [ \$i -eq 30 ]; then
                                            echo "❌ Application failed to respond after 30 attempts"
                                            echo "=== Container Logs ==="
                                            docker-compose logs --tail=50 || echo "Could not retrieve container logs"
                                            echo "=== Final Container Status ==="
                                            docker-compose ps
                                            docker ps -a
                                        else
                                            echo "⏳ Application not ready yet, waiting 10 seconds..."
                                            sleep 10
                                        fi
                                    fi
                                done
                                
                                # Final deployment status
                                echo "=== Final Deployment Status ==="
                                docker-compose ps
                                echo ""
                                echo "🎉 Deployment completed!"
                                echo "Application should be accessible at: http://\$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo \"[PUBLIC_IP]\"):8080"
                                echo "Database is running on port 3306"
                            '
                        """
                    }
                }
            }
        }
    }
}