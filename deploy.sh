#!/bin/bash
set -e

# =========================================================================
# ⚙️ REPOSITORY CONFIGURATION MATRIX
# =========================================================================
GITHUB_USER="QuickFactory"
GITHUB_REPO="ai-deployment"
BRANCH="main"
RAW_URL="https://githubusercontent.com{GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

echo "=========================================================="
echo " 🚀 INITIATING AGNOSTIC AI-STACK ORCHESTRATION LAYER"
echo "=========================================================="

# 1. Enforce administrative privilege boundary checks
if [ "$EUID" -ne 0 ]; then
  echo "❌ Operational Fault: Please execute this installer using sudo (sudo ./deploy.sh)"
  exit 1
fi

echo "=== Step 1: Processing Host Dependencies ==="
apt-get update && apt-get upgrade -y
apt-get install -y curl gnupg lsb-release openssl git uidmap

echo "=== Step 2: Provisioning Swap Memory Limits (4GB Tier Guard) ==="
# Prevents low-resource VPS nodes from locking up during database initialization blocks
if [ ! -f /swapfile ]; then
    echo "💾 Allocation window missed. Formatting 4GB swap tracking file..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "✅ Swap allocation written successfully."
else
    echo "ℹ️  Active swap configuration file detected. Skipping tracking block."
fi

echo "=== Step 3: Resolving Ingestion Workspace Layouts ==="
mkdir -p /opt/ai-stack && cd /opt/ai-stack

echo "=== Step 4: Syncing Core Declarative Blueprints ==="
# Retreives container architecture blueprints dynamically from your master branch tracking tree
curl -sSL "${RAW_URL}/docker-compose.yml" -o docker-compose.yml
curl -sSL "${RAW_URL}/librechat.yaml" -o librechat.yaml

echo "=== Step 5: Evaluating Storage Topology (Optional Volume Mapping) ==="
# Scans system path markers dynamically to isolate mounting matrices across AWS, DigitalOcean, or Hetzner
if mountpoint -q /mnt/ai-volume; then
    echo "📁 External Block Storage detected under /mnt/ai-volume. Routing high-write backends..."
    BASE_DATA_DIR="/mnt/ai-volume"
else
    echo "💽 No partition mount identified. Scaling localized internal cluster directories..."
    BASE_DATA_DIR="/opt/ai-stack/local_data"
fi

# Dynamically provision folders on the resolved storage target path
mkdir -p "${BASE_DATA_DIR}/hermes_data"
mkdir -p "${BASE_DATA_DIR}/rag_data"
mkdir -p "${BASE_DATA_DIR}/searxng"
mkdir -p "${BASE_DATA_DIR}/librechat_data"
mkdir -p "${BASE_DATA_DIR}/mongo_data"
mkdir -p "${BASE_DATA_DIR}/postgres_data"

# Create relative symlinks so that docker-compose can remain 100% platform-independent
ln -sfn "${BASE_DATA_DIR}/hermes_data" ./hermes_data
ln -sfn "${BASE_DATA_DIR}/rag_data" ./rag_data
ln -sfn "${BASE_DATA_DIR}/searxng" ./searxng
ln -sfn "${BASE_DATA_DIR}/librechat_data" ./librechat_data
ln -sfn "${BASE_DATA_DIR}/mongo_data" ./mongo_data
ln -sfn "${BASE_DATA_DIR}/postgres_data" ./postgres_data

# Write minimal settings structure if SearXNG properties are missing
if [ ! -f ./searxng/settings.yml ]; then
    cat <<EOF > ./searxng/settings.yml
use_default_settings: true
server:
  port: 8080
  bind_address: "0.0.0.0"
  secret_key: "$(openssl rand -hex 16)"
EOF
fi

echo "=== Step 6: Setting Up Docker Engine Package Streams ==="
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://docker.com | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://docker.com $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Step 7: Injecting Dual-Stack IPv6 Routing Rules to Daemon ==="
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80",
  "ip6tables": true
}
EOF
systemctl restart docker || true

echo "=== Step 8: Initializing Interactive Parameter Compilation ==="
if [ -f .env ]; then
    echo "⚠️  An active environment configuration payload (.env) is already present."
    echo "   Aborting installation to prevent overwriting keys. Modify files directly if adjusting."
    exit 0
fi

echo "----------------------------------------------------------"
echo "  📝 USER METADATA INPUT REQUIRED"
echo "----------------------------------------------------------"
read -p "Enter your application address domain (e.g. ai.enabled.world): " USER_DOMAIN
read -p "Enter your Let's Encrypt notification Email: " USER_EMAIL
read -p "Paste your OpenRouter API Credential key (sk-or-...): " USER_OR_KEY
read -p "Enter DuckDNS Subdomain identifier (e.g. mysub for mysub.duckdns.org): " DUCK_SUB
read -p "Enter DuckDNS secret automation account Token: " DUCK_TOKEN

echo "=== Step 9: Dispatched Routing Sync to DuckDNS Registry ==="
DUCK_RESPONSE=$(curl -s "https://duckdns.org{DUCK_SUB}&token=${DUCK_TOKEN}&ip=")

if [ "$DUCK_RESPONSE" != "OK" ]; then
    echo "❌ Operational Halt: DuckDNS server synchronization rejected credentials."
    exit 1
else
    echo "✅ Remote address points cleanly to current VPS infrastructure mapping."
fi

# Secure high-entropy localized cryptographic variable generation logic
RANDOM_JWT=$(openssl rand -hex 24)
RANDOM_REFRESH=$(openssl rand -hex 24)
RANDOM_DB_PASS=$(openssl rand -hex 16)
RANDOM_HERMES=$(openssl rand -hex 16)

cat <<EOT > .env
LIBRECHAT_DOMAIN=$USER_DOMAIN
LETSENCRYPT_EMAIL=$USER_EMAIL
OPENROUTER_API_KEY=$USER_OR_KEY
DUCKDNS_SUBDOMAIN=$DUCK_SUB
DUCKDNS_TOKEN=$DUCK_TOKEN
HERMES_INTERNAL_TOKEN=$RANDOM_HERMES
LIBRECHAT_JWT_SECRET=$RANDOM_JWT
LIBRECHAT_JWT_REFRESH_SECRET=$RANDOM_REFRESH
RAG_INTERNAL_API_KEY=$(openssl rand -hex 16)
POSTGRES_DB_PASSWORD=$RANDOM_DB_PASS
DISCORD_BOT_TOKEN=change_me_if_needed
DISCORD_CHANNEL_ID=change_me_if_needed
EOT

echo "=== Step 10: Spawning Native Application Container Pipeline ==="
docker compose --env-file .env up -d

echo "=========================================================="
echo " 🎉 OPERATIONAL DEPLOYMENT ARCHITECTURE IS LIVE!"
echo " 🌐 UI Interface Domain Endpoint: https://${USER_DOMAIN}"
echo "=========================================================="
