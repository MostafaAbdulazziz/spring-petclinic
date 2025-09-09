pipeline {
    agent none // Agent will be defined per stage for containerization

    tools {
        maven 'maven3911' // Name must match your Jenkins Global Tool Configuration
        jdk 'JDK-21'      // Name must match your Jenkins Global Tool Configuration
    }

    environment {
        // --- Credentials ---
        // Loaded from Jenkins Credentials. Use the ID you set in Jenkins.
        SONAR_TOKEN             = credentials('9091') // SonarQube token for analysis
        DOCKERHUB_CREDS         = credentials('dockerhub_token')
        EC2_SSH_KEY             = credentials('ec2-app-deployer-key') // SSH key for EC2 access

        // --- Configuration ---
        DOCKERHUB_USERNAME      = "mostafaabdelazziz" // Replace with your Docker Hub username
        DOCKER_IMAGE_NAME       = "${DOCKERHUB_USERNAME}/petclinic"
        
        // --- EC2 Staging Environment ---
        // These can be simple strings or Jenkins credentials if you prefer
        EC2_APP_HOST            = "ec2-13-48-136-47.eu-north-1.compute.amazonaws.com"
        EC2_DB_HOST             = "ec2-13-48-136-47.eu-north-1.compute.amazonaws.com"

        // --- Database Connection Details for the App ---
        DB_HOST_INTERNAL        = "petclinic" // The service name in docker-compose
        DB_NAME                 = "petclinic"
        DB_USER                 = "petclinic"
        DB_PASS_SECRET          = "petclinic" // Stored securely in Jenkins
    }

    stages {
        stage('Build and Analyze in Parallel') {
            parallel {
                stage('Build and Test') {
                    agent {
                        docker {
                            image 'maven:3.9.6-eclipse-temurin-17'
                            args '-v /var/lib/jenkins/.m2:/root/.m2' // Cache Maven dependencies
                        }
                    }
                    steps {
                        script {
                            try {
                                sh "mvn clean install"
                                // Stash 
                                stash name: 'jar-file', includes: 'target/*.jar'
                            } catch (e) {
                                currentBuild.result = 'FAILURE'
                                error "Build and Test stage failed!"
                            }
                        }
                    }
                }
                stage('SonarQube Analysis') {
                    agent any 
                    steps {
                        script {
                            try {
                                withSonarQubeEnv('SonarQubeServer') { 
                                    sh "mvn sonar:sonar -Dsonar.login=${SONAR_TOKEN}"
                                }
                            } catch (e) {
                                currentBuild.result = 'FAILURE'
                                error "SonarQube Analysis stage failed!"
                            }
                        }
                    }
                }
            }
        }

        stage('Build & Push Docker Image') {
            agent any
            steps {
                script {
                    // Unstash the jar file from the build stage
                    unstash 'jar-file'
                    
                    // Use the Docker Pipeline plugin for registry login
                    docker.withRegistry("https://index.docker.io/v1/", DOCKERHUB_CREDS) {
                        def customImage = docker.build(DOCKER_IMAGE_NAME, ".")
                        
                        // Push the image with the build number as a tag
                        customImage.push("${env.BUILD_NUMBER}")
                        // Also push it with the 'latest' tag for convenience
                        customImage.push("latest")
                    }
                }
            }
        }

        stage('Install Docker on Staging Host') {
            agent any
            steps {
                script {
                    sshagent([EC2_SSH_KEY]) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ${EC2_STAGING_HOST} '
                                set -e # Exit immediately if a command fails

                                # Get the username from the host string (e.g., ec2-user)
                                STAGING_USER=\$(echo "${EC2_STAGING_HOST}" | cut -d"@" -f1)

                                # --- Install Docker ---
                                if ! command -v docker &> /dev/null
                                then
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

                                # --- Install Docker Compose ---
                                if ! command -v docker-compose &> /dev/null
                                then
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
        }

        
        stage('Deploy to Staging') {
            agent any
            steps {
                script {
                    // Use the SSH Agent plugin to securely connect to EC2
                    sshagent([EC2_SSH_KEY]) {
                        
                        // --- 1. Deploy/Update Database Instance ---
                        // We copy the compose file and run it. It will only recreate if needed.
                        sh """
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_DB_HOST}:~/
                            ssh -o StrictHostKeyChecking=no ${EC2_DB_HOST} '
                                export MYSQL_ROOT_PASSWORD=root
                                export MYSQL_DATABASE=${DB_NAME}
                                export MYSQL_USER=${DB_USER}
                                export MYSQL_PASSWORD=${DB_PASS_SECRET}
                                
                                docker-compose up -d db
                            '
                        """

                        // --- 2. Deploy/Update Application Instance ---
                        // We copy the compose file, pull the latest image, and restart the service.
                        sh """
                            scp -o StrictHostKeyChecking=no docker-compose.yml ${EC2_APP_HOST}:~/
                            ssh -o StrictHostKeyChecking=no ${EC2_APP_HOST} '
                                export TAG=${env.BUILD_NUMBER}
                                export DB_HOST=${EC2_DB_HOST.split('@')[1]} // Pass the public DNS of the DB server
                                export DB_NAME=${DB_NAME}
                                export DB_USER=${DB_USER}
                                export DB_PASS=${DB_PASS_SECRET}
                                
                                docker-compose pull app // Pull the new image version from Docker Hub
                                docker-compose up -d --no-deps app // Restart only the app service
                            '
                        """
                    }
                }
            }
        }
    }
}
