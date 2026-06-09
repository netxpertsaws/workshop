#!/usr/bin/env bash
# =============================================================================
# EC2 Setup Script — Workshop Site (Java + Tomcat + MySQL on one instance)
# Target: Amazon Linux 2  OR  Ubuntu 22.04
# Usage : sudo bash ec2-setup.sh
#
# Optionally pre-set credentials via environment variables before running:
#   sudo MYSQL_ROOT_PASSWORD='MyRootPw!' APP_DB_PASSWORD='MyAppPw!' \
#        bash ec2-setup.sh
# Otherwise strong random passwords are generated automatically and saved to
#   /root/.workshop-db-credentials  (chmod 600)
# =============================================================================
set -euo pipefail

TOMCAT_VERSION="9.0.86"
TOMCAT_HOME="/opt/tomcat"
WAR_NAME="workshop-site.war"
APP_USER="tomcat"

APP_DB_NAME="workshop_db"
APP_DB_USER="workshop_user"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

gen_password() {
    # 20-char password — pure bash, no pipes (avoids SIGPIPE under set -o pipefail).
    local pw="" chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local n=${#chars} i
    for ((i = 0; i < 20; i++)); do
        pw="${pw}${chars:$((RANDOM % n)):1}"
    done
    printf '%s' "$pw"
}

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-$(gen_password)}"
APP_DB_PASSWORD="${APP_DB_PASSWORD:-$(gen_password)}"

# ──────────────────────────────────────────────────────────────────────────
echo "=== 1/9  Detect OS ==="
if   [ -f /etc/amazon-linux-release ];        then OS="amazon"
elif [ -f /etc/lsb-release ];                 then OS="ubuntu"
else echo "  Unsupported OS"; exit 1
fi
echo "  OS: $OS"

# ──────────────────────────────────────────────────────────────────────────
echo "=== 2/9  Install Java 11 ==="
if [ "$OS" = "amazon" ]; then
    yum -y update -q
    amazon-linux-extras install -y java-openjdk11
    yum -y install wget tar
else
    apt-get update -y -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk wget tar
fi
java -version

# Resolve the real JAVA_HOME (path differs between Ubuntu and Amazon Linux)
JAVA_HOME_PATH=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
echo "  JAVA_HOME: $JAVA_HOME_PATH"

# ──────────────────────────────────────────────────────────────────────────
echo "=== 3/9  Create tomcat system user ==="
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd -m -U -d "$TOMCAT_HOME" -s /bin/false "$APP_USER"
fi

# ──────────────────────────────────────────────────────────────────────────
echo "=== 4/9  Install Tomcat $TOMCAT_VERSION ==="
if [ ! -d "$TOMCAT_HOME/bin" ]; then
    cd /tmp
    wget -q "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
    mkdir -p "$TOMCAT_HOME"
    tar -xzf "apache-tomcat-${TOMCAT_VERSION}.tar.gz" -C "$TOMCAT_HOME" --strip-components=1
    rm -f "apache-tomcat-${TOMCAT_VERSION}.tar.gz"
fi
chown -R "$APP_USER:$APP_USER" "$TOMCAT_HOME"
chmod +x "$TOMCAT_HOME"/bin/*.sh

# ──────────────────────────────────────────────────────────────────────────
echo "=== 5/9  Install MySQL 8 ==="
if [ "$OS" = "amazon" ]; then
    if ! command -v mysqld >/dev/null 2>&1; then
        yum -y localinstall https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm || true
        rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 || true
        yum -y install mysql-community-server
    fi
    systemctl enable --now mysqld
    MYSQL_SVC="mysqld"
else
    if ! command -v mysql >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
    fi
    systemctl enable --now mysql
    MYSQL_SVC="mysql"
fi

# Wait until the server is responding
echo "  Waiting for MySQL to be ready..."
for i in $(seq 1 30); do
    if mysqladmin --silent ping >/dev/null 2>&1; then break; fi
    sleep 1
done

# ──────────────────────────────────────────────────────────────────────────
echo "=== 6/9  Configure MySQL root password ==="

# ADMIN array is the connection that has full root-equivalent privileges.
# After this step it always points to mysql -u root -p<known password>.
ADMIN=()

if [ "$OS" = "amazon" ]; then
    # Amazon Linux: read the temporary root password from the log
    TEMP_PASS=$(grep 'temporary password' /var/log/mysqld.log 2>/dev/null \
                | tail -1 | awk '{print $NF}' || true)
    if [ -n "$TEMP_PASS" ]; then
        mysql --connect-expired-password -u root -p"$TEMP_PASS" <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
SQL
    fi

else
    # Ubuntu/Debian: prefer the debian-sys-maint admin (always created by apt
    # install of mysql-server). Fall back to socket-auth then to existing
    # known root password.
    if [ -f /etc/mysql/debian.cnf ] \
            && mysql --defaults-file=/etc/mysql/debian.cnf -e "SELECT 1" >/dev/null 2>&1; then
        echo "  Authenticated via /etc/mysql/debian.cnf"
        mysql --defaults-file=/etc/mysql/debian.cnf <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
SQL
    elif mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        echo "  Authenticated via socket"
        mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
SQL
    elif mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        echo "  Root already set to expected password — continuing"
    else
        echo "  ERROR: Could not authenticate as MySQL admin."
        echo "  Either:"
        echo "    a) Pass the existing root password via env var:"
        echo "       sudo MYSQL_ROOT_PASSWORD='your-existing-password' bash ec2-setup.sh"
        echo "    b) Reset MySQL completely:"
        echo "       sudo systemctl stop mysql"
        echo "       sudo apt-get remove --purge mysql-server mysql-client mysql-common"
        echo "       sudo rm -rf /var/lib/mysql /etc/mysql"
        echo "       sudo bash ec2-setup.sh"
        exit 1
    fi
fi

# From here on, the root password is known — use it for everything else.
ADMIN=(mysql -u root "-p$MYSQL_ROOT_PASSWORD")

# ──────────────────────────────────────────────────────────────────────────
echo "=== 7/9  Apply schema and create app DB user ==="
if [ ! -f "$SCRIPT_DIR/schema.sql" ]; then
    echo "  ERROR: schema.sql not found in $SCRIPT_DIR"
    exit 1
fi
"${ADMIN[@]}" < "$SCRIPT_DIR/schema.sql"

"${ADMIN[@]}" <<SQL
CREATE USER IF NOT EXISTS '$APP_DB_USER'@'localhost' IDENTIFIED BY '$APP_DB_PASSWORD';
ALTER USER '$APP_DB_USER'@'localhost' IDENTIFIED BY '$APP_DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON $APP_DB_NAME.* TO '$APP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
SQL

# Save generated credentials so the user can retrieve them later
CRED_FILE="/root/.workshop-db-credentials"
cat > "$CRED_FILE" <<EOF
# ===========================================================================
#  Workshop Site — Generated MySQL credentials
#  Generated on: $(date)
#  IMPORTANT: This file is chmod 600. Keep it private.
# ===========================================================================
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
APP_DB_USER=$APP_DB_USER
APP_DB_PASSWORD=$APP_DB_PASSWORD
APP_DB_NAME=$APP_DB_NAME
EOF
chmod 600 "$CRED_FILE"

# ──────────────────────────────────────────────────────────────────────────
echo "=== 8/9  Configure /etc/tomcat-env for the application ==="
ENV_FILE="/etc/tomcat-env"
cat > "$ENV_FILE" <<EOF
# Database connection — auto-generated by ec2-setup.sh
# To regenerate the app password manually:
#   sudo mysql -u root -p
#   ALTER USER 'workshop_user'@'localhost' IDENTIFIED BY 'new-password';
#   then update DB_PASSWORD below and restart tomcat
DB_HOST=localhost
DB_PORT=3306
DB_NAME=$APP_DB_NAME
DB_USER=$APP_DB_USER
DB_PASSWORD=$APP_DB_PASSWORD
DB_POOL_SIZE=5
EOF
chmod 600 "$ENV_FILE"
chown "$APP_USER:$APP_USER" "$ENV_FILE"

# ──────────────────────────────────────────────────────────────────────────
echo "=== 9/9  Install Tomcat systemd service and deploy WAR ==="

# 9a. Install systemd unit with the detected JAVA_HOME substituted in
sed "s|__JAVA_HOME__|$JAVA_HOME_PATH|g" "$SCRIPT_DIR/tomcat.service" \
    > /etc/systemd/system/tomcat.service
systemctl daemon-reload
systemctl enable tomcat

# 9b. Locate the WAR — check the deployment dir first, then ../target,
#     then the project root's target/ (Maven build output)
WAR_PATH=""
for candidate in \
    "$SCRIPT_DIR/${WAR_NAME}" \
    "$SCRIPT_DIR/../target/${WAR_NAME}" \
    "$(pwd)/../target/${WAR_NAME}" \
    "$(pwd)/target/${WAR_NAME}"; do
    if [ -f "$candidate" ]; then
        WAR_PATH="$(readlink -f "$candidate")"
        break
    fi
done

if [ -n "$WAR_PATH" ]; then
    # Remove any previous extracted webapp folder so Tomcat re-extracts cleanly
    rm -rf "$TOMCAT_HOME/webapps/${WAR_NAME%.war}" "$TOMCAT_HOME/webapps/${WAR_NAME}"
    cp "$WAR_PATH" "$TOMCAT_HOME/webapps/${WAR_NAME}"
    chown "$APP_USER:$APP_USER" "$TOMCAT_HOME/webapps/${WAR_NAME}"
    echo "  WAR deployed from: $WAR_PATH"
else
    echo "  NOTE: $WAR_NAME not found in:"
    echo "    - $SCRIPT_DIR/"
    echo "    - $SCRIPT_DIR/../target/"
    echo "    - $(pwd)/../target/"
    echo "    - $(pwd)/target/"
    echo "  Build it first with 'mvn clean package', or copy the WAR into"
    echo "  $SCRIPT_DIR/ and re-run this script."
fi

# 9c. Start Tomcat and verify
systemctl restart tomcat
sleep 4

if systemctl is-active --quiet tomcat; then
    echo "  ✓ Tomcat is running"
else
    echo "  ✗ Tomcat failed to start. Recent journal log:"
    journalctl -u tomcat --no-pager -n 25 || true
    echo ""
    echo "  Also check: sudo tail /opt/tomcat/logs/catalina.out"
    echo "  And: sudo systemctl status tomcat"
fi

# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Setup complete!"
echo ""
echo "  Database credentials saved to:"
echo "    /root/.workshop-db-credentials  (chmod 600)"
echo "  View them with:  sudo cat /root/.workshop-db-credentials"
echo ""
echo "  App URL:  http://<EC2-PUBLIC-IP>:8080/workshop-site/"
echo ""
echo "  Useful commands:"
echo "    sudo systemctl status tomcat"
echo "    sudo journalctl -u tomcat -f"
echo "    sudo mysql -u root -p\$MYSQL_ROOT_PASSWORD $APP_DB_NAME"
echo "============================================================"
