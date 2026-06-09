#!/usr/bin/env bash
# =============================================================================
# jenkins-setup.sh — installs Jenkins, Java 17, Maven, Git on a fresh EC2.
# Target: Amazon Linux 2  OR  Ubuntu 22.04 / 24.04
# Run on a separate EC2 instance (not the app server).
# Usage: sudo bash jenkins-setup.sh
# =============================================================================
set -euo pipefail

echo "=== 1/5  Detect OS ==="
if   [ -f /etc/amazon-linux-release ];  then OS="amazon"
elif [ -f /etc/lsb-release ];           then OS="ubuntu"
else echo "  Unsupported OS"; exit 1
fi
echo "  OS: $OS"

# ─────────────────────────────────────────────────────────────────────────
echo "=== 2/5  Install Java 17 (required by Jenkins LTS) and Maven, Git ==="
if [ "$OS" = "amazon" ]; then
    yum -y update -q
    amazon-linux-extras enable corretto8 || true
    yum -y install java-17-amazon-corretto maven git wget
else
    apt-get update -y -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk maven git wget gnupg
fi
java -version
mvn -version | head -1

# ─────────────────────────────────────────────────────────────────────────
echo "=== 3/5  Install Jenkins LTS ==="
if [ "$OS" = "amazon" ]; then
    wget -qO /etc/yum.repos.d/jenkins.repo \
        https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || true
    yum -y install jenkins
else
    wget -qO /usr/share/keyrings/jenkins-keyring.asc \
        https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] " \
         "https://pkg.jenkins.io/debian-stable binary/" \
        > /etc/apt/sources.list.d/jenkins.list
    apt-get update -y -q
    apt-get install -y jenkins
fi
systemctl enable --now jenkins

# ─────────────────────────────────────────────────────────────────────────
echo "=== 4/5  Open firewall (informational only — set this in your AWS SG) ==="
echo "  Make sure your EC2 security group allows inbound TCP 8080 from your IP."

# ─────────────────────────────────────────────────────────────────────────
echo "=== 5/5  Print initial admin password ==="
echo "  Waiting up to 30s for Jenkins to start..."
for i in $(seq 1 30); do
    if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then break; fi
    sleep 1
done

if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    PW=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
    echo ""
    echo "============================================================"
    echo "  Jenkins is up!"
    echo ""
    echo "  URL:               http://<this-ec2-ip>:8080/"
    echo "  Initial password:  $PW"
    echo ""
    echo "  Next steps:"
    echo "   1. Open URL in browser, paste the password"
    echo "   2. Install suggested plugins"
    echo "   3. Create admin user"
    echo "   4. Go to Manage Jenkins → Tools and add:"
    echo "        - JDK named 'JDK-11' (path: \$(readlink -f /usr/bin/javac | sed 's|/bin/javac||')"
    echo "          — OR add openjdk-11 separately if not yet installed)"
    echo "        - Maven named 'Maven-3.9'"
    echo "   5. Manage Jenkins → Credentials → add SSH key for ec2-ssh-key"
    echo "   6. Create Pipeline job pointing to your GitHub repo"
    echo "============================================================"
else
    echo "  Jenkins didn't start. Check: sudo journalctl -u jenkins -n 50"
fi
