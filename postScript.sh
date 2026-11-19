
#!/bin/bash
set -e

APP_DIR="/home/ubuntu"

# Install Node.js 22 if missing
if ! command -v node >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi

# Install Nginx and PM2
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx
npm install -g pm2

# Set ownership only on application files
for path in \
    API_MESSAGES.md Dockerfile LICENSE README.md buildspec.yml \
    dist-health docker-compose.yml generate-secrets.js nginx \
    node_modules package.json package-lock.json postScript.sh \
    src templates tsconfig.health.json tsconfig.json
do
    if [ -e "$APP_DIR/$path" ]; then
        chown -R ubuntu:ubuntu "$APP_DIR/$path"
    fi
done

# Protect environment file
if [ -f "$APP_DIR/.env" ]; then
    chown ubuntu:ubuntu "$APP_DIR/.env"
    chmod 600 "$APP_DIR/.env"
fi

# Install production dependencies and start the API
sudo -u ubuntu -H bash -c "
    cd '$APP_DIR'
    npm install --omit=dev

    if pm2 describe mysafety-health >/dev/null 2>&1; then
        pm2 restart mysafety-health
    else
        pm2 start dist-health/health.js --name mysafety-health
    fi

    pm2 save
"

# Configure Nginx
cat > /etc/nginx/sites-available/mysafety-health <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/mysafety-health /etc/nginx/sites-enabled/mysafety-health
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable --now nginx
systemctl reload nginx
