// ============================================================================
//  Jenkinsfile — Workshop Site CI/CD with full provisioning
//
//  Pipeline flow:
//    1. Checkout    — pull source from GitHub
//    2. Build WAR   — mvn clean package
//    3. Test        — mvn test
//    4. Archive WAR — keep build artefact in Jenkins
//    5. Provision   — install Java, Tomcat, MySQL on App Server (idempotent)
//    6. Deploy WAR  — copy WAR + invoke deploy hook on the App Server
//
//  Prerequisites on the Jenkins server:
//    - Tools: 'Maven-3.9' and 'JDK-11' configured in Manage Jenkins → Tools
//    - Credential: 'ec2-ssh-key' (SSH Username with private key, user=ubuntu)
//    - Plugins: Pipeline, Git, SSH Agent, GitHub
//
//  Prerequisites on the App Server (one-time, ~30 seconds of manual work):
//    - Fresh Ubuntu 22.04 / 24.04 EC2 instance
//    - Jenkins SSH public key appended to /home/ubuntu/.ssh/authorized_keys
//    - Default 'ubuntu' user has passwordless sudo (AWS AMI default)
// ============================================================================

pipeline {
    agent any

    tools {
        maven 'Maven-3.9'
        jdk   'JDK-11'
    }

    parameters {
        string(
            name: 'APP_HOST',
            defaultValue: 'ubuntu@172.31.11.224',
            description: 'SSH target — user@ip of the App Server. Example: ubuntu@13.234.56.78'
        )
        booleanParam(
            name: 'PROVISION',
            defaultValue: true,
            description: 'Install/update Java, Tomcat, MySQL and the deploy hook on the App Server. Safe to leave on — script is idempotent.'
        )
        booleanParam(
            name: 'SKIP_DEPLOY',
            defaultValue: false,
            description: 'Build and test only, do not deploy the WAR.'
        )
    }

    environment {
    WAR_NAME   = 'workshop-site.war'
    REMOTE_DIR = "/tmp/workshop-provision"
    APP_HOST   = "${params.APP_HOST}"
}

    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                sh 'git log -1 --pretty=format:"%h  %an  %s"'
            }
        }

        stage('Build WAR') {
            steps {
                sh 'mvn -B -DskipTests clean package'
            }
        }

        stage('Test') {
            steps {
                sh 'mvn -B test'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                }
            }
        }
stage('SonarQube Analysis') {
    steps {
        withSonarQubeEnv('SonarQube') {          
            sh '''
                mvn -B sonar:sonar \
                    -Dsonar.projectKey=workshop-site \
                    -Dsonar.projectName="Workshop Registration Site"
            '''
        }
    }
}

stage('Quality Gate') {
    steps {
        timeout(time: 5, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true   
        }
    }
}
        

        stage('Archive WAR') {
            steps {
                archiveArtifacts artifacts: "target/${env.WAR_NAME}", fingerprint: true
            }
        }

        stage('Provision App Server') {
            when {
                allOf {
                    expression { params.PROVISION }
                    expression { params.APP_HOST?.trim() && !params.APP_HOST.contains('YOUR_APP_SERVER_IP') }
                }
            }
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh '''
                        set -eu
                        SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

                        echo "═══════════════════════════════════════════════════════════"
                        echo "  Provisioning App Server: ${APP_HOST}"
                        echo "═══════════════════════════════════════════════════════════"

                        echo ""
                        echo "→ [1/3] Uploading provisioning files..."
                        ssh ${SSH_OPTS} "${APP_HOST}" "mkdir -p ${REMOTE_DIR}"
                        scp ${SSH_OPTS} \
                            deployment/ec2-setup.sh    \
                            deployment/tomcat.service  \
                            deployment/schema.sql      \
                            deployment/deploy.sh       \
                            "${APP_HOST}:${REMOTE_DIR}/"

                        echo ""
                        echo "→ [2/3] Installing Java, Tomcat, MySQL"
                        echo "        (3-5 min on a fresh server; seconds on re-runs)"
                        echo ""
                        ssh ${SSH_OPTS} "${APP_HOST}" "
                            cd ${REMOTE_DIR} &&
                            chmod +x ec2-setup.sh &&
                            sudo bash ec2-setup.sh
                        "

                        echo ""
                        echo "→ [3/3] Installing deploy hook (/usr/local/bin/deploy-workshop)..."
                        ssh ${SSH_OPTS} "${APP_HOST}" "
                            sudo cp ${REMOTE_DIR}/deploy.sh /usr/local/bin/deploy-workshop &&
                            sudo chmod 755 /usr/local/bin/deploy-workshop &&
                            sudo chown root:root /usr/local/bin/deploy-workshop &&
                            echo 'ubuntu ALL=(root) NOPASSWD: /usr/local/bin/deploy-workshop' \
                                | sudo tee /etc/sudoers.d/deploy-workshop > /dev/null &&
                            sudo chmod 440 /etc/sudoers.d/deploy-workshop
                        "

                        echo ""
                        echo "✓ App Server provisioning complete."
                    '''
                }
            }
        }

        stage('Deploy WAR to App Server') {
            when {
                allOf {
                    expression { !params.SKIP_DEPLOY }
                    expression { params.APP_HOST?.trim() && !params.APP_HOST.contains('YOUR_APP_SERVER_IP') }
                }
            }
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh '''
                        set -eu
                        SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

                        echo "→ Uploading ${WAR_NAME} to App Server..."
                        scp ${SSH_OPTS} "target/${WAR_NAME}" "${APP_HOST}:/tmp/${WAR_NAME}"

                        echo "→ Triggering deploy hook..."
                        ssh ${SSH_OPTS} "${APP_HOST}" \
                            "sudo /usr/local/bin/deploy-workshop /tmp/${WAR_NAME}"

                        echo "✓ Deployment complete."
                    '''
                }
            }
        }
    }

    post {
        success {
            script {
                def appIp = (params.APP_HOST ?: '').split('@').last()
                echo "═══════════════════════════════════════════════════════════"
                echo "  ✓ Build #${env.BUILD_NUMBER} succeeded"
                echo "  Site: http://${appIp}:8080/workshop-site/"
                echo "═══════════════════════════════════════════════════════════"
            }
        }
        failure {
            echo "✗ Build #${env.BUILD_NUMBER} failed — check the Console Output above."
        }
    }
}
