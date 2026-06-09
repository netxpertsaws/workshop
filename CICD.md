# CI/CD with GitHub and Jenkins

End-to-end: push to GitHub → Jenkins builds → deploys to EC2 automatically.

## Architecture

```
   ┌──────────────┐     git push      ┌─────────────────┐
   │ Your laptop  │ ─────────────────▶│  GitHub repo    │
   └──────────────┘                   └────────┬────────┘
                                               │ webhook (POST)
                                               ▼
                              ┌────────────────────────────────┐
                              │  Jenkins EC2 (port 8080)       │
                              │   - Checkout                   │
                              │   - mvn clean package          │
                              │   - mvn test                   │
                              │   - archive WAR                │
                              │   - scp WAR → App EC2          │
                              │   - ssh run deploy-workshop    │
                              └────────────────┬───────────────┘
                                               │ SSH (port 22)
                                               ▼
                              ┌────────────────────────────────┐
                              │  App EC2 (Tomcat + MySQL)      │
                              │   /usr/local/bin/deploy-       │
                              │     workshop swaps in the WAR  │
                              │   Tomcat auto-redeploys        │
                              └────────────────────────────────┘
```

Two EC2 instances: one for **the app** (already deployed), one for **Jenkins**.

---

## Part 1 — Push the source to GitHub

### 1.1 Create the GitHub repo

In GitHub: **New repository** → name it `workshop-site` → leave it empty
(no README, no .gitignore — the project already has them) → **Create**.

### 1.2 Push from your local checkout

From inside the `workshop-site/` folder:

```bash
git init -b main
git add .
git commit -m "Initial commit: workshop site with registration and admin view"
git remote add origin git@github.com:<your-user>/workshop-site.git
git push -u origin main
```

Verify in GitHub that all files are there. `target/`, `*.war`, and `*.pem`
are excluded by `.gitignore`.

---

## Part 2 — Prepare the App EC2

The app EC2 needs:

- The `deploy-workshop` script installed
- Passwordless `sudo` for that one script (so Jenkins can call it over SSH)

### 2.1 Install the deploy script

```bash
# On the App EC2
sudo cp ~/worksh/workshop-site/deployment/deploy.sh /usr/local/bin/deploy-workshop
sudo chmod 755 /usr/local/bin/deploy-workshop
sudo chown root:root /usr/local/bin/deploy-workshop
```

### 2.2 Allow Jenkins to invoke it without password

```bash
# On the App EC2
sudo tee /etc/sudoers.d/deploy-workshop > /dev/null <<'EOF'
ubuntu ALL=(root) NOPASSWD: /usr/local/bin/deploy-workshop
EOF
sudo chmod 440 /etc/sudoers.d/deploy-workshop

# Test it
sudo -n /usr/local/bin/deploy-workshop  # prints usage, no password prompt
```

Use `ec2-user` instead of `ubuntu` on Amazon Linux 2.

---

## Part 3 — Stand up the Jenkins EC2

### 3.1 Launch a Jenkins instance

| Setting        | Value                                |
|----------------|--------------------------------------|
| Name           | `jenkins-ci`                         |
| AMI            | Ubuntu 22.04                         |
| Type           | `t3.small`                           |
| Key pair       | reuse or create                      |
| Inbound 22     | your IP                              |
| Inbound 8080   | your IP (Jenkins UI)                 |

### 3.2 Run the bootstrap script

```bash
# From your laptop
scp -i your-key.pem deployment/jenkins-setup.sh ubuntu@<jenkins-ip>:/tmp/
ssh -i your-key.pem ubuntu@<jenkins-ip>
sudo bash /tmp/jenkins-setup.sh
```

Installs Java 17, Maven, Git, Jenkins. Prints the **initial admin password**
(also saved at `/var/lib/jenkins/secrets/initialAdminPassword`).

### 3.3 Complete the Jenkins UI setup

Open `http://<jenkins-ip>:8080/` in your browser:

1. Paste the initial password
2. **Install suggested plugins**
3. Create an admin user
4. **Manage Jenkins → System** → set Jenkins URL to `http://<jenkins-ip>:8080/`
5. **Manage Jenkins → Plugins** → install if missing:
   - **Pipeline**, **Git**, **SSH Agent**, **GitHub**

### 3.4 Configure Tools (Manage Jenkins → Tools)

- **JDK installations** — name **`JDK-11`**
  - "Install automatically" → Adoptium Temurin OpenJDK 11
- **Maven installations** — name **`Maven-3.9`**
  - "Install automatically" → 3.9.x

These exact names match the `tools` block in `Jenkinsfile`.

### 3.5 Set up the SSH credential

On the **Jenkins EC2**:

```bash
sudo -u jenkins ssh-keygen -t ed25519 -f /var/lib/jenkins/.ssh/id_deploy -N ""
sudo cat /var/lib/jenkins/.ssh/id_deploy.pub      # copy this
```

On the **App EC2**:

```bash
echo "<paste public key>" | sudo tee -a /home/ubuntu/.ssh/authorized_keys
sudo chmod 600 /home/ubuntu/.ssh/authorized_keys
```

Test from Jenkins EC2:

```bash
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/id_deploy \
    -o StrictHostKeyChecking=no \
    ubuntu@<app-ec2-ip> 'echo Jenkins SSH OK'
```

In **Jenkins UI**:

1. **Manage Jenkins → Credentials → System → Global → Add Credentials**
2. Kind: **SSH Username with private key**
3. ID: **`ec2-ssh-key`** (must match Jenkinsfile)
4. Username: `ubuntu`
5. Private key: paste contents of `/var/lib/jenkins/.ssh/id_deploy`

---

## Part 4 — Create the pipeline job

### 4.1 New job

**New Item** → name `workshop-site` → **Pipeline** → OK.

Configure:

- **GitHub project**: tick → enter repo URL
- **Pipeline**:
  - Definition: **Pipeline script from SCM**
  - SCM: **Git**
  - Repo URL: `https://github.com/<your-user>/workshop-site.git`
  - Branch: `*/main`
- **Build Triggers**: tick **GitHub hook trigger for GITScm polling**

Save.

### 4.2 First manual build

Click **Build with Parameters**, set:

- **EC2_HOST**: `ubuntu@<app-ec2-ip>`
- **SKIP_DEPLOY**: unchecked

Hit **Build**. All five stages should go green.

### 4.3 GitHub webhook

GitHub repo → **Settings → Webhooks → Add webhook**:

- Payload URL: `http://<jenkins-ip>:8080/github-webhook/`
- Content type: `application/json`
- Events: **Just the push event**

Now every push to `main` triggers a build and deploy.

---

## Part 5 — Daily workflow

```bash
vim src/main/webapp/index.html
git add -A
git commit -m "Update workshop card colors"
git push

# Watch the build at http://<jenkins-ip>:8080/job/workshop-site/
# ~2 minutes later the change is live at http://<app-ec2-ip>:8080/workshop-site/
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Permission denied (publickey)" from Jenkins SSH | Re-check `authorized_keys` perms (600) and `.ssh` (700) on App EC2 |
| "sudo: a password is required" during deploy | `/etc/sudoers.d/deploy-workshop` missing or wrong syntax — validate with `sudo visudo -cf /etc/sudoers.d/deploy-workshop` |
| "mvn: command not found" | Tool names in Manage Jenkins → Tools don't match `Maven-3.9` / `JDK-11` |
| Webhook fires but no build | Check `Manage Jenkins → System Log` for `/github-webhook/` requests; ensure Jenkins URL is reachable from GitHub |
| Build fails on `archive` step | `target/workshop-site.war` not produced — check Maven build logs |

---

## Hardening for production

- **HTTPS**: nginx + Let's Encrypt in front of both Jenkins and Tomcat
- **Jenkins agents**: don't build on the controller — provision worker nodes
- **Credentials**: move `DB_PASSWORD` to AWS Secrets Manager
- **Approvals**: add an `input` step before Deploy on the main branch
- **Tests**: replace placeholder `mvn test` with real JUnit 5 unit tests
