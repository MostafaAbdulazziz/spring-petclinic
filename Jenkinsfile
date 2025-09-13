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
                        docker tag spring-petclinic:1.0 ec2-51-21-244-131.eu-north-1.compute.amazonaws.com:8082/docker-hosted/spring-petclinic:1.0
                        echo "${NEXUS_PASSWORD}" | docker login ec2-51-21-244-131.eu-north-1.compute.amazonaws.com:8082 -u "${NEXUS_USERNAME}" --password-stdin
                        docker push ec2-51-21-244-131.eu-north-1.compute.amazonaws.com:8082/docker-hosted/spring-petclinic:1.0
                    """
                }
            }
        }



    //     stage('Install Docker on Staging Host') {
    //         agent any
    //         steps {
    //             // The sshagent step handles SSH credentials directly. Pass the ID as a string.
    //             sshagent(['ec2-app-deployer-key']) {
    //                 sh """
    //                     ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
    //                         set -e
    //                         STAGING_USER=\$(echo "${EC2_STAGING_HOST}" | cut -d"@" -f1)

    //                         # --- Install Docker ---
    //                         if ! command -v docker &> /dev/null; then
    //                             echo "Docker not found. Installing..."
    //                             sudo yum update -y
    //                             sudo yum install -y docker
    //                             sudo systemctl start docker
    //                             sudo systemctl enable docker
    //                             sudo usermod -aG docker \$STAGING_USER
    //                             echo "Docker installed successfully."
    //                         else
    //                             echo "Docker is already installed."
    //                         fi

    //                         # --- Install Docker Compose ---
    //                         if ! command -v docker-compose &> /dev/null; then
    //                             echo "Docker Compose not found. Installing..."
    //                             sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    //                             sudo chmod +x /usr/local/bin/docker-compose
    //                             echo "Docker Compose installed successfully."
    //                         else
    //                             echo "Docker Compose is already installed."
    //                         fi
    //                     '
    //                 """
    //             }
    //         }
    //     }
        
    //     stage('Deploy to Staging') {
    //         agent any
    //         steps {
    //             // Load the DB password credential here to use it in the shell script
    //             withCredentials([string(credentialsId: 'petclinic_db_password', variable: 'DB_PASS_SECRET')]) {
    //                 sshagent(['ec2-app-deployer-key']) {
    //                     sh """
    //                         # Copy the compose file to the single EC2 instance
    //                         scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_STAGING_HOST}:~/

    //                         # SSH into the instance to deploy both containers
    //                         ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
    //                             # Export variables for docker-compose to read from this shell environment
    //                             export TAG=${env.BUILD_NUMBER}
    //                             export DB_NAME=${DB_NAME}
    //                             export DB_USER=${DB_USER}
    //                             export DB_PASS=${DB_PASS_SECRET}
    //                             export MYSQL_ROOT_PASSWORD=${DB_PASS_SECRET}
                                
    //                             # Pull the new application image version
    //                             docker-compose pull app

    //                             # Bring up both services. Compose will only recreate what has changed.
    //                             docker-compose up -d
    //                         '
    //                     """
    //                 }
    //             }
    //         }
    //     }
    // }
            }   
}

