pipeline {
    agent none // Agent will be defined per stage

    // The 'tools' block has been REMOVED as the Docker image contains Maven and Java.

    environment {
        // --- Configuration ---
        DOCKERHUB_USERNAME      = "mostafaabdelazziz"
        DOCKER_IMAGE_NAME       = "${DOCKERHUB_USERNAME}/petclinic"
        EC2_STAGING_HOST        = "ubuntu@ec2-13-48-68-86.eu-north-1.compute.amazonaws.com"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        DB_PASS_SECRET          = "petclinic"
        NEXUS_REGISTRY          = "ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082"
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
                        docker build -t spring-petclinic:1.0 .
                        docker tag spring-petclinic:1.0 ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:${BUILD_NUMBER}
                        echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin
                        docker push ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:${BUILD_NUMBER}
                    """
                }
            }
        }

        stage('Deploy to EC2') {
            agent any
            steps {
                withCredentials([
                    sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER'),
                    string(credentialsId: 'nexus_docker_username', variable: 'NEXUS_USERNAME'),
                    string(credentialsId: 'nexus_docker_password', variable: 'NEXUS_PASSWORD')
                ]) {
                    script {
                        // Create the docker-compose file content
                        def dockerComposeContent = """version: '3.8'

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD:-root}
      MYSQL_DATABASE: \${DB_NAME:-${DB_NAME}}
      MYSQL_USER: \${DB_USER:-${DB_USER}}
      MYSQL_PASSWORD: \${DB_PASS:-${DB_PASS_SECRET}}
    ports:
      - "3306:3306"
      - "33060:33060"
    volumes:
      - mysql-db-1:/var/lib/mysql
    networks:
      - petclinic-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      timeout: 20s
      retries: 10

  petclinic:
    image: \${NEXUS_REGISTRY:-${NEXUS_REGISTRY}}/docker-hosted/spring-petclinic:\${BUILD_NUMBER:-${BUILD_NUMBER}}
    environment:
      - SPRING_PROFILES_ACTIVE=mysql
      - SPRING_DATASOURCE_URL=jdbc:mysql://db:3306/\${DB_NAME:-${DB_NAME}}
      - SPRING_DATASOURCE_USERNAME=\${DB_USER:-${DB_USER}}
      - SPRING_DATASOURCE_PASSWORD=\${DB_PASS:-${DB_PASS_SECRET}}
      - SPRING_JPA_HIBERNATE_DDL_AUTO=update
      - SPRING_JPA_SHOW_SQL=true
      - SPRING_JPA_DATABASE_PLATFORM=org.hibernate.dialect.MySQL8Dialect
    ports:
      - "8080:8080"
    networks:
      - petclinic-network
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

networks:
  petclinic-network:
    driver: bridge

volumes:
  mysql-db-1:
"""
                        
                        // Write docker-compose file to workspace
                        writeFile file: 'docker-compose-prod.yml', text: dockerComposeContent
                        
                        // Create environment file
                        def envContent = """NEXUS_REGISTRY=${NEXUS_REGISTRY}
BUILD_NUMBER=${BUILD_NUMBER}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS_SECRET}
MYSQL_ROOT_PASSWORD=root
"""
                        writeFile file: '.env', text: envContent
                        
                        // Deploy to EC2
                        sh """
                            # Copy files to EC2
                            scp -i \${SSH_KEY} -o StrictHostKeyChecking=no docker-compose-prod.yml .env ${EC2_STAGING_HOST}:~/
                            
                            # SSH to EC2 and deploy
                            ssh -i \${SSH_KEY} -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} << 'EOF'
                                # Login to Nexus registry
                                echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin
                                
                                # Stop existing containers if running
                                if [ -f docker-compose-prod.yml ]; then
                                    docker-compose -f docker-compose-prod.yml down
                                fi
                                
                                # Pull latest image
                                docker pull ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:${BUILD_NUMBER}
                                
                                # Start services
                                docker-compose -f docker-compose-prod.yml up -d
                                
                                # Wait for services to be healthy
                                echo "Waiting for services to start..."
                                sleep 30
                                
                                # Check if services are running
                                docker-compose -f docker-compose-prod.yml ps
                                
                                # Test application health
                                echo "Testing application health..."
                                for i in {1..10}; do
                                    if curl -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
                                        echo "Application is healthy!"
                                        break
                                    else
                                        echo "Attempt \$i: Application not ready yet, waiting..."
                                        sleep 10
                                    fi
                                    if [ \$i -eq 10 ]; then
                                        echo "Application health check failed after 10 attempts"
                                        exit 1
                                    fi
                                done
EOF
                        """
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo "Pipeline completed successfully! Application deployed to ${EC2_STAGING_HOST}"
        }
        failure {
            echo "Pipeline failed. Check logs for details."
        }
        always {
            // Clean up workspace
            cleanWs()
        }
    }
}