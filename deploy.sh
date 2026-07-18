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
echo " 🚀 INITIATING PORTABLE AI-STACK DEPLOYMENT ENGINE"
echo "=========================================================="

# 1. Enforce administrative privilege boundary checks
if [ "$EUID" -ne 0 ]; then
  echo "❌ Operational Fault: Please execute this installer using sudo (sudo ./deploy.sh)"
  exit 1
fi

echo "=== Step 1: Processing Host Dependencies ==="
apt-get update && apt-get upgrade -y
apt-get install -y curl gnupg lsb-release openssl git uidmap e2fsprogs

echo "=== Step 2: Provisioning Swap Memory Limits (4GB Tier Guard) ==="
if [ ! -f /swapfile ]; then
    echo "💾 Formatting 4GB swap tracking file..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "✅ Swap allocation written successfully."
else
    echo "ℹ️  Active swap configuration file detected. Skipping."
fi

echo "=== Step 3: Resolving Workspace Layouts ==="
mkdir -p /opt/ai-stack && cd /opt/ai-stack

echo "=== Step 4: Syncing Core Declarative Blueprints ==="
curl -sSL "${RAW_URL}/docker-compose.yml" -o docker-compose.yml
curl -sSL "${RAW_URL}/librechat.yaml" -o librechat.yaml

echo "=== Step 5: Evaluating Adaptive Volume Topology ==="
mkdir -p /mnt/ai-volume

# Detect if an unmounted physical block device exists
TARGET_DEVICE=""
if [ -b /dev/vdb ]; then
    TARGET_DEVICE="/dev/vdb"
elif [ -b /dev/sdb ]; then
    TARGET_DEVICE="/dev/sdb"
fi

if [ -not -z "$TARGET_DEVICE" ]; then
    echo "🔍 Physical block device found at ${TARGET_DEVICE}."
    # Format to ext4 ONLY if it doesn't already contain a filesystem signature
    if ! blkid "$TARGET_DEVICE" > /dev/null 2>&1; then
        echo "💽 Formatting unallocated block array to ext4..."
        mkfs.ext4 -F "$TARGET_DEVICE"
    fi
    
    # Mount the volume if not already handled
    if ! mountpoint -q /mnt/ai-volume; then
        mount "$TARGET_DEVICE" /mnt/ai-volume
        # Add to fstab for persistent boots across power cycles
        if ! grep -q "/mnt/ai-volume" /etc/fstab; then
            echo "${TARGET_DEVICE} /mnt/ai-volume ext4 defaults,noatime,nofail 0 0" >> /etc/fstab
        fi
    fi
fi

# Set runtime workspace direction mapping path
if mountpoint -q /mnt/ai-volume; then
    echo "📁 External Block Storage active. Offloading data to Volume..."
    BASE_DATA_DIR="/mnt/ai-volume"
else
    echo "💽 No block device active. Falling back to local storage structures..."
    BASE_DATA_DIR="/opt/ai-stack/local_data"
fi

# Dynamically provision storage layers
mkdir -p "${BASE_DATA_DIR}/hermes_data"
mkdir -p "${BASE_DATA_DIR}/rag_data"
mkdir -p "${BASE_DATA_DIR}/searxng"
mkdir -p "${BASE_DATA_DIR}/librechat_data"
mkdir -p "${BASE_DATA_DIR}/mongo_data"
mkdir -p "${BASE_DATA_DIR}/postgres_data"

# Universal cross-platform relative symlinks
ln -sfn "${BASE_DATA_DIR}/hermes_data" ./hermes_data
ln -sfn "${BASE_DATA_DIR}/rag_data" ./rag_data
ln -sfn "${BASE_DATA_DIR}/searxng" ./searxng
ln -sfn "${BASE_DATA_DIR}/librechat_data" ./librechat_data
ln -sfn "${BASE_DATA_DIR}/mongo_data" ./mongo_data
ln -sfn "${BASE_DATA_DIR}/postgres_data" ./postgres_data

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
echo "deb [arch=$(dpkg --print-architecture) signed-by scheduled-by=/etc/apt/keyrings/docker.gpg] https://docker.com $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Step 7: Injecting Dual-Stack IPv6 Routing Rules ==="
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
    echo "⚠️  An active environment configuration payload (.env) is already present. Aborting."
    exit 0
fi

echo "----------------------------------------------------------"
echo "  📝 USER METADATA INPUT REQUIRED"
echo "----------------------------------------------------------"
read -p "Enter your application address domain (e.g. ai.enabled.world): " USER_DOMAIN
read -p "Enter your Let's Encrypt notification Email: " USER_EMAIL
read -p "Paste your OpenRouter API key (sk-or-...): " USER_OR_KEY
read -p "Enter DuckDNS Subdomain identifier: " DUCK_SUB
read -p "Enter DuckDNS account Token: " DUCK_TOKEN

echo "=== Step 9: Dispatched Routing Sync to DuckDNS Registry ==="
DUCK_RESPONSE=$(curl -s "https://duckdns.org{DUCK_SUB}&token=${DUCK_TOKEN}&ip=")

if [ "$DUCK_RESPONSE" != "OK" ]; then
    echo "❌ Operational Halt: DuckDNS server synchronization rejected credentials."
    exit 1
fi

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

echo "=== Step 10: Spawning Application Container Pipeline ==="
docker compose --env-file .env up -d

echo "=========================================================="
echo " 🎉 OPERATIONAL DEPLOYMENT ARCHITECTURE IS LIVE!"
echo "=========================================================="
