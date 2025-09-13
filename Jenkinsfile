pipeline {
    agent none

    environment {
        DOCKERHUB_USERNAME      = "mostafaabdelazziz"
        DOCKER_IMAGE_NAME       = "${DOCKERHUB_USERNAME}/petclinic"
        EC2_STAGING_HOST        = "ec2-user@ec2-13-48-136-47.eu-north-1.compute.amazonaws.com"
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        NEXUS_REGISTRY          = "ec2-51-21-244-131.eu-north-1.compute.amazonaws.com:8082"
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
                        # Configure Docker daemon to use insecure registry
                        echo '{"insecure-registries":["${NEXUS_REGISTRY}"]}' | sudo tee /etc/docker/daemon.json
                        sudo systemctl restart docker
                        
                        # Wait for Docker to restart
                        sleep 10
                        
                        # Build and tag image
                        docker build -t spring-petclinic:1.0 .
                        docker tag spring-petclinic:1.0 ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:1.0
                        
                        # Login and push
                        echo "${NEXUS_PASSWORD}" | docker login ${NEXUS_REGISTRY} -u "${NEXUS_USERNAME}" --password-stdin
                        docker push ${NEXUS_REGISTRY}/docker-hosted/spring-petclinic:1.0
                    """
                }
            }
        }
    }
}
