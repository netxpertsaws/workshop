# Deployment Guide — Workshop Site

This guide takes you from **zero** to a **live registration website** running
on AWS EC2 in about **15 minutes**.

At the end you will have:

- A public URL → `http://<your-ec2-ip>:8080/workshop-site/`
- Java + Tomcat 9 + MySQL 8 all running on **one EC2 instance**
- Registrations stored in a MySQL `registrations` table

---

## What you need before starting

| Item                | Required                                    |
|---------------------|---------------------------------------------|
| AWS account         | with EC2 access                             |
| Local computer      | macOS / Linux / Windows (WSL or Git Bash)   |
| Java JDK 11+        | for building the WAR (Step 1)               |
| Maven 3.6+          | for building the WAR (Step 1)               |
| SSH client          | built-in on macOS/Linux; Git Bash on Win    |

---

## STEP 1 — Install Java and Maven on your computer (one-time)

You only ever do this once.

**macOS:**
```bash
brew install openjdk@11 maven
```

**Ubuntu / Debian:**
```bash
sudo apt update
sudo apt install -y openjdk-11-jdk maven
```

**Windows:** install JDK 11 from <https://adoptium.net> and Maven from
<https://maven.apache.org/download.cgi>, then add both to your PATH.

Verify:
```bash
java -version        # must show 11 or higher
mvn -version
```

> **Don't want to install Java locally?** Skip to *Appendix A: Build with
> Docker* at the bottom of this file.

---

## STEP 2 — Build the WAR file

Open a terminal in the `workshop-site` folder (where `pom.xml` lives) and run:

```bash
mvn clean package
```

This produces the deployment artefact at:

```
target/workshop-site.war
```

That single file contains all the compiled Java, HTML, CSS, and JavaScript.

---

## STEP 3 — Launch an EC2 instance

In the AWS Console → EC2 → **Launch Instance**:

| Setting              | Value                                          |
|----------------------|------------------------------------------------|
| **Name**             | `workshop-site`                                |
| **AMI**              | Amazon Linux 2  *(or Ubuntu 22.04)*            |
| **Instance type**    | `t3.small`  *(2 GB RAM minimum)*               |
| **Key pair**         | create new, or pick existing — download `.pem` |
| **Storage**          | 20 GB gp3 (default)                            |

**Security group inbound rules:**

| Type       | Port  | Source        | Purpose                |
|------------|-------|---------------|------------------------|
| SSH        | 22    | My IP         | so you can connect     |
| Custom TCP | 8080  | Anywhere      | so visitors see the site |

> Do **NOT** open port 3306. MySQL stays on `localhost` for security.

Launch the instance. Once it shows **Running**, copy its **Public IPv4
address** — you'll use it in the next step.

---

## STEP 4 — Upload files to EC2

Open a terminal on your computer in the `workshop-site` folder. Set three
variables to your values:

```bash
# Fill these in:
KEY=~/Downloads/workshop-site.pem      # path to your .pem file
IP=12.34.56.78                          # EC2 public IP
USER=ec2-user                           # 'ec2-user' for Amazon Linux, 'ubuntu' for Ubuntu
```

Fix key file permissions (macOS/Linux only):
```bash
chmod 400 "$KEY"
```

Create a deploy folder on the EC2 and upload everything:

```bash
# 1. Create a folder on EC2
ssh -i "$KEY" "$USER@$IP" 'mkdir -p ~/deploy'

# 2. Upload the WAR + all deployment files into that folder
scp -i "$KEY" target/workshop-site.war   "$USER@$IP:~/deploy/"
scp -i "$KEY" deployment/ec2-setup.sh    "$USER@$IP:~/deploy/"
scp -i "$KEY" deployment/tomcat.service  "$USER@$IP:~/deploy/"
scp -i "$KEY" deployment/schema.sql      "$USER@$IP:~/deploy/"
```

After this, your EC2 instance has the following files in `~/deploy/`:

```
workshop-site.war      ← the application
ec2-setup.sh           ← installer script
tomcat.service         ← systemd unit
schema.sql             ← MySQL schema
```

---

## STEP 5 — SSH into EC2 and run the installer

Connect to the instance:

```bash
ssh -i "$KEY" "$USER@$IP"
```

You're now logged in to EC2. Run **one** command:

```bash
cd ~/deploy
sudo bash ec2-setup.sh
```

Wait 3-5 minutes. The script installs everything in this order:

1. Java 11
2. Apache Tomcat 9
3. MySQL 8
4. Configures MySQL with auto-generated strong passwords
5. Applies the schema (`workshop_db.registrations`)
6. Creates the app database user (`workshop_user@localhost`)
7. Writes credentials into `/etc/tomcat-env`
8. Deploys the WAR
9. Starts Tomcat as a systemd service

When it finishes, you'll see:

```
============================================================
  Setup complete!
  App URL:  http://<EC2-PUBLIC-IP>:8080/workshop-site/
============================================================
```

---

## STEP 6 — Open the website

In your browser, navigate to:

```
http://<your-ec2-ip>:8080/workshop-site/
```

You should see the landing page with the two workshops and the registration
form. Try submitting a test registration — you should see a green
**"Registration received"** message.

---

## STEP 7 — View or change the database credentials (optional)

The setup script auto-generates strong random passwords. To view them:

```bash
# On the EC2 instance
sudo cat /root/.workshop-db-credentials
```

Output looks like:

```
MYSQL_ROOT_PASSWORD=Ab3xKj9LpQwErTy12345
APP_DB_USER=workshop_user
APP_DB_PASSWORD=Mn8oPqRsTuVwXyZ9876aB
APP_DB_NAME=workshop_db
```

To **specify your own passwords** instead, set them before running step 5:

```bash
sudo MYSQL_ROOT_PASSWORD='YourRootPw!' \
     APP_DB_PASSWORD='YourAppPw!'   \
     bash ec2-setup.sh
```

To **check the registrations** that have been submitted:

```bash
# On the EC2 instance
source /root/.workshop-db-credentials
mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$APP_DB_NAME" \
      -e "SELECT * FROM registrations ORDER BY id DESC;"
```

---

## Updating the app later

When you make changes to the code and want to redeploy:

```bash
# On your local computer
mvn clean package
scp -i "$KEY" target/workshop-site.war "$USER@$IP:~/deploy/"

# Then on EC2
ssh -i "$KEY" "$USER@$IP" '
  sudo systemctl stop tomcat &&
  sudo rm -rf /opt/tomcat/webapps/workshop-site* &&
  sudo cp ~/deploy/workshop-site.war /opt/tomcat/webapps/ &&
  sudo chown tomcat:tomcat /opt/tomcat/webapps/workshop-site.war &&
  sudo systemctl start tomcat
'
```

---

## Troubleshooting

### "I can't reach the URL"

```bash
# On EC2
sudo systemctl status tomcat        # is Tomcat running?
sudo journalctl -u tomcat -n 50     # recent log lines
sudo ss -tlnp | grep 8080           # is port 8080 listening?
```

Also check your **security group** allows port 8080 inbound from your IP.

### "Form submission fails"

```bash
# Check Tomcat application logs
sudo tail -f /opt/tomcat/logs/catalina.out

# Check the database is reachable
source /root/.workshop-db-credentials
mysql -u "$APP_DB_USER" -p"$APP_DB_PASSWORD" "$APP_DB_NAME" -e "SELECT 1;"
```

If the DB query fails, restart everything:
```bash
sudo systemctl restart mysqld    # 'mysql' on Ubuntu
sudo systemctl restart tomcat
```

### "I need to re-run the setup script"

The script is **idempotent** — running it again is safe. It will skip steps
already completed (Java already installed, Tomcat folder exists, MySQL user
exists, etc.).

---

## Appendix A — Build with Docker (no local Java required)

If you don't want to install Java/Maven locally, build the WAR in a Docker
container instead:

```bash
# From the workshop-site folder
docker run --rm -v "$(pwd):/app" -w /app \
  maven:3.9-eclipse-temurin-11 \
  mvn clean package
```

The output appears at `target/workshop-site.war` as usual. Then continue
from Step 3.

---

## Appendix B — File map

```
workshop-site/
├── DEPLOYMENT.md                          ← this file
├── README.md                              ← short overview
├── pom.xml                                ← Maven build (WAR packaging)
├── src/main/
│   ├── java/com/mayooran/workshop/
│   │   ├── DatabaseConfig.java            ← env-var based DB config
│   │   └── RegistrationServlet.java       ← POST /api/register
│   ├── resources/schema.sql               ← MySQL schema (canonical)
│   └── webapp/
│       ├── WEB-INF/web.xml
│       ├── index.html                     ← landing page + form
│       ├── css/styles.css
│       └── js/register.js
└── deployment/                            ← what you upload to EC2
    ├── ec2-setup.sh                       ← installer script
    ├── tomcat.service                     ← systemd unit
    └── schema.sql                         ← copy used at install time
```
