#!/usr/bin/env bash
# =============================================================================
# deploy-workshop  —  invoked by Jenkins via SSH to swap in a new WAR.
#
# Install location: /usr/local/bin/deploy-workshop  (chmod 755)
# Usage:            sudo /usr/local/bin/deploy-workshop /path/to/workshop-site.war
#
# Tomcat auto-deploys WARs dropped into webapps/, so no full restart is needed.
# A short post-copy pause lets the deployer extract the WAR before the next
# request comes in.
# =============================================================================
set -euo pipefail

WAR_SOURCE="${1:-}"
TOMCAT_HOME="/opt/tomcat"
TOMCAT_USER="tomcat"
WAR_NAME="workshop-site.war"
APP_DIR_NAME="workshop-site"

if [ -z "$WAR_SOURCE" ]; then
    echo "Usage: $0 /path/to/workshop-site.war" >&2
    exit 1
fi
if [ ! -f "$WAR_SOURCE" ]; then
    echo "ERROR: WAR file not found: $WAR_SOURCE" >&2
    exit 1
fi

TARGET="$TOMCAT_HOME/webapps/$WAR_NAME"
BACKUP="$TOMCAT_HOME/webapps/$WAR_NAME.bak"

echo "[deploy-workshop] Backing up current WAR (if any)…"
if [ -f "$TARGET" ]; then
    cp -f "$TARGET" "$BACKUP"
fi

echo "[deploy-workshop] Removing extracted webapp folder so Tomcat re-extracts…"
rm -rf "$TOMCAT_HOME/webapps/$APP_DIR_NAME"

echo "[deploy-workshop] Copying new WAR into webapps/…"
cp "$WAR_SOURCE" "$TARGET"
chown "$TOMCAT_USER:$TOMCAT_USER" "$TARGET"
chmod 644 "$TARGET"

echo "[deploy-workshop] Waiting for Tomcat auto-deploy (10s)…"
sleep 10

# Light health check — verify the webapp directory got extracted
if [ -d "$TOMCAT_HOME/webapps/$APP_DIR_NAME" ]; then
    echo "[deploy-workshop] ✓ App extracted at $TOMCAT_HOME/webapps/$APP_DIR_NAME"
else
    echo "[deploy-workshop] ⚠ App folder not yet extracted — check catalina.out:"
    echo "    sudo tail $TOMCAT_HOME/logs/catalina.out"
    exit 2
fi

echo "[deploy-workshop] Cleaning up source WAR in /tmp/…"
rm -f "$WAR_SOURCE"

echo "[deploy-workshop] Done. Open the site to verify."
