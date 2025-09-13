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
                        docker tag spring-petclinic:1.0 ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082/docker-hosted/spring-petclinic:1.0
                        echo "${NEXUS_PASSWORD}" | docker login ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082 -u "${NEXUS_USERNAME}" --password-stdin
                        docker push ec2-13-61-184-206.eu-north-1.compute.amazonaws.com:8082/docker-hosted/spring-petclinic:1.0
                    """
                }
            }
        }




            }   
}

