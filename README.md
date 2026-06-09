# Workshop Registration Site

Java + MySQL web app for registering participants in the
**Containers & Kubernetes at Scale** and **Cloud-Scale DevOps Strategy**
workshops.

→ **For first-time deployment, see [DEPLOYMENT.md](DEPLOYMENT.md)** ←
→ **For GitHub setup + CI/CD pipeline, see [CICD.md](CICD.md)** ←

---

## What's in this project

```
workshop-site/
├── DEPLOYMENT.md      ← start here — full step-by-step deploy guide
├── README.md          ← this file
├── pom.xml            ← Maven build → produces target/workshop-site.war
├── src/main/
│   ├── java/          ← Java servlets (registration endpoint, DB config)
│   ├── resources/     ← MySQL schema
│   └── webapp/        ← HTML, CSS, JavaScript
└── deployment/        ← scripts to install on EC2
    ├── ec2-setup.sh   ← one-command installer (Java + Tomcat + MySQL)
    ├── tomcat.service ← systemd unit
    └── schema.sql     ← copy of the DB schema
```

## Tech stack

| Layer        | Technology                                        |
|--------------|---------------------------------------------------|
| Frontend     | HTML5 + CSS3 + vanilla JavaScript (no framework)  |
| Backend      | Java 11 servlets (Servlet API 4.0)                |
| DB pool      | HikariCP                                          |
| Database     | MySQL 8                                           |
| Build        | Maven → WAR                                       |
| Container    | Apache Tomcat 9                                   |
| Hosting      | Amazon EC2 (single instance: Tomcat + MySQL)      |

## Configuration

All database settings are read from **environment variables** —
no secrets in code:

| Variable        | Required | Default     |
|-----------------|----------|-------------|
| `DB_HOST`       | no       | `localhost` |
| `DB_PORT`       | no       | `3306`      |
| `DB_NAME`       | **yes**  | —           |
| `DB_USER`       | **yes**  | —           |
| `DB_PASSWORD`   | **yes**  | —           |
| `DB_POOL_SIZE`  | no       | `5`         |

The EC2 setup script writes these to `/etc/tomcat-env` automatically.

## Quick reference

```bash
# Build the WAR
mvn clean package

# Deploy to EC2 (see DEPLOYMENT.md for full guide)
scp target/workshop-site.war deployment/* user@ec2-ip:~/deploy/
ssh user@ec2-ip 'cd ~/deploy && sudo bash ec2-setup.sh'

# View site
open http://<ec2-ip>:8080/workshop-site/
```

## API endpoint

`POST /api/register` — JSON request:

```json
{
  "studentName": "Abdul Ahad",
  "studentNo":   "TRN-2026-0042",
  "workshop":    "Containers & Kubernetes at Scale"
}
```

Returns `201` on success with the generated registration ID.

---

**Author:** Mayooran · Independent Trainer & Consultant · Sri Lanka
