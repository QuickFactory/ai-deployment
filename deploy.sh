#!/bin/bash
set -e

# =========================================================================
# Hermes-first AI stack deployer (LibreChat optional)
# Domains: one DuckDNS subdomain per vhost, all updated in a single call.
# =========================================================================
GITHUB_USER="QuickFactory"
GITHUB_REPO="ai-deployment"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: run with sudo (sudo ./deploy.sh)"; exit 1
fi

echo "=== Step 1: Host dependencies ==="
apt-get update && apt-get upgrade -y
apt-get install -y curl gnupg lsb-release openssl git uidmap e2fsprogs gettext-base

echo "=== Step 2: 4GB swap guard ==="
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile && chmod 600 /swapfile
  mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "=== Step 3: Workspace ==="
mkdir -p /opt/ai-stack && cd /opt/ai-stack
mkdir -p nginx-conf/vhost.d ingest-image

echo "=== Step 4: Fetch blueprints ==="
curl -sSL "${RAW_URL}/docker-compose.yml" -o docker-compose.yml
curl -sSL "${RAW_URL}/nginx-conf/api-location.conf.template" -o nginx-conf/api-location.conf.template
curl -sSL "${RAW_URL}/ingest-image/Dockerfile" -o ingest-image/Dockerfile
curl -sSL "${RAW_URL}/ingest-image/ingest_watcher.py" -o ingest-image/ingest_watcher.py

echo "=== Step 5: Volume topology ==="
mkdir -p /mnt/ai-volume
TARGET_DEVICE=""
[ -b /dev/vdb ] && TARGET_DEVICE="/dev/vdb"
[ -z "$TARGET_DEVICE" ] && [ -b /dev/sdb ] && TARGET_DEVICE="/dev/sdb"
if [ -n "$TARGET_DEVICE" ]; then
  blkid "$TARGET_DEVICE" >/dev/null 2>&1 || mkfs.ext4 -F "$TARGET_DEVICE"
  if ! mountpoint -q /mnt/ai-volume; then
    mount "$TARGET_DEVICE" /mnt/ai-volume
    grep -q "/mnt/ai-volume" /etc/fstab || \
      echo "${TARGET_DEVICE} /mnt/ai-volume ext4 defaults,noatime,nofail 0 0" >> /etc/fstab
  fi
fi
if mountpoint -q /mnt/ai-volume; then
  BASE_DATA_DIR="/mnt/ai-volume"
else
  BASE_DATA_DIR="/opt/ai-stack/local_data"
fi
for d in hermes_data rag_data searxng librechat_data mongo_data postgres_data \
         ingest/inbox ingest/processed ingest/failed; do
  mkdir -p "${BASE_DATA_DIR}/${d}"
done
for l in hermes_data rag_data searxng librechat_data mongo_data postgres_data ingest; do
  ln -sfn "${BASE_DATA_DIR}/${l}" "./${l}"
done

if [ ! -f ./searxng/settings.yml ]; then
cat <<EOF > ./searxng/settings.yml
use_default_settings: true
server:
  port: 8080
  bind_address: "0.0.0.0"
  secret_key: "$(openssl rand -hex 16)"
EOF
fi

echo "=== Step 6: Docker engine ==="
mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Step 7: Dual-stack IPv6 for Docker ==="
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{ "ipv6": true, "fixed-cidr-v6": "fd00::/80", "ip6tables": true }
EOF
systemctl restart docker || true

echo "=== Step 8: Interactive configuration ==="
if [ -f .env ]; then
  echo "WARN: .env already present. Aborting to avoid clobbering secrets."; exit 0
fi

echo "----------------------------------------------------------"
echo " Each public service gets its own DuckDNS subdomain."
echo " Enter DuckDNS subdomain NAMES only (without .duckdns.org),"
echo " or full custom domains if you CNAME them yourself."
echo "----------------------------------------------------------"
read -p "DuckDNS subdomain for the Hermes DASHBOARD (e.g. my-hermes): " DUCK_DASH
read -p "DuckDNS subdomain for the Hermes API      (e.g. my-hermes-api): " DUCK_API
read -p "Let's Encrypt notification email: " USER_EMAIL
read -p "OpenRouter API key (sk-or-...): " USER_OR_KEY
read -p "DuckDNS account token: " DUCK_TOKEN
read -p "Install LibreChat frontend? [y/N]: " INSTALL_LC

DUCK_SUBS="${DUCK_DASH},${DUCK_API}"
LC_BLOCK=""
if [[ "$INSTALL_LC" =~ ^[Yy]$ ]]; then
  read -p "DuckDNS subdomain for LibreChat (e.g. my-hermes-chat): " DUCK_LC
  DUCK_SUBS="${DUCK_SUBS},${DUCK_LC}"
  LC_BLOCK=$(cat <<EOT
COMPOSE_PROFILES=librechat
LIBRECHAT_DOMAIN=${DUCK_LC}.duckdns.org
LIBRECHAT_JWT_SECRET=$(openssl rand -hex 24)
LIBRECHAT_JWT_REFRESH_SECRET=$(openssl rand -hex 24)
EOT
)
  curl -sSL "${RAW_URL}/librechat.yaml" -o librechat.yaml
fi

echo "=== Step 9: DuckDNS sync (all subdomains, one call) ==="
DUCK_RESPONSE=$(curl -s "https://www.duckdns.org/update?domains=${DUCK_SUBS}&token=${DUCK_TOKEN}&ip=")
if [ "$DUCK_RESPONSE" != "OK" ]; then
  echo "ERROR: DuckDNS rejected the update for: ${DUCK_SUBS}"; exit 1
fi

AI_DOMAIN="${DUCK_DASH}.duckdns.org"
API_DOMAIN="${DUCK_API}.duckdns.org"
HERMES_INTERNAL_TOKEN=$(openssl rand -hex 24)

echo "=== Step 10: Generating 5 client API keys ==="
KEYS_FILE=/opt/ai-stack/api-keys.txt
: > "$KEYS_FILE"; chmod 600 "$KEYS_FILE"
{
  echo 'map $http_authorization $api_client {'
  echo '    default "";'
  for i in 1 2 3 4 5; do
    KEY="hk-$(openssl rand -hex 20)"
    echo "    \"Bearer ${KEY}\" \"client${i}\";"
    echo "client${i}  ${KEY}" >> "$KEYS_FILE"
  done
  echo '}'
} > nginx-conf/api-keys.conf

# Render the API vhost auth snippet (key check + token swap)
export HERMES_INTERNAL_TOKEN
sed "s/__HERMES_INTERNAL_TOKEN__/${HERMES_INTERNAL_TOKEN}/" \
  nginx-conf/api-location.conf.template > "nginx-conf/vhost.d/${API_DOMAIN}_location"

echo "=== Step 11: Writing .env ==="
cat <<EOT > .env
AI_DOMAIN=${AI_DOMAIN}
API_DOMAIN=${API_DOMAIN}
LETSENCRYPT_EMAIL=${USER_EMAIL}
OPENROUTER_API_KEY=${USER_OR_KEY}
DUCKDNS_SUBDOMAINS=${DUCK_SUBS}
DUCKDNS_TOKEN=${DUCK_TOKEN}
HERMES_INTERNAL_TOKEN=${HERMES_INTERNAL_TOKEN}
RAG_INTERNAL_API_KEY=$(openssl rand -hex 16)
POSTGRES_DB_PASSWORD=$(openssl rand -hex 16)
OCR_LANGUAGES=eng
INGEST_POLL_INTERVAL=20
DISCORD_BOT_TOKEN=change_me_if_needed
DISCORD_CHANNEL_ID=change_me_if_needed
${LC_BLOCK}
EOT
chmod 600 .env

echo "=== Step 12: Launch ==="
docker compose --env-file .env up -d --build

echo "=== Step 13: Waiting for HTTPS to come up (valid certificates) ==="
# curl WITHOUT -k: only succeeds once a browser-trusted (Let's Encrypt)
# cert is served. nginx-proxy's interim self-signed default keeps failing,
# so this genuinely waits for issuance, not just for the port to open.
DOMAINS_TO_CHECK="${AI_DOMAIN} ${API_DOMAIN}"
if [[ "$INSTALL_LC" =~ ^[Yy]$ ]]; then
  DOMAINS_TO_CHECK="${DOMAINS_TO_CHECK} ${DUCK_LC}.duckdns.org"
fi
CERT_FAILURES=0
for d in $DOMAINS_TO_CHECK; do
  printf "  %-45s " "$d"
  ok=0
  for i in $(seq 1 60); do   # up to 10 minutes per domain
    if curl -s -o /dev/null --max-time 10 "https://${d}"; then
      echo "OK"
      ok=1
      break
    fi
    printf "."
    sleep 10
  done
  if [ "$ok" -ne 1 ]; then
    echo " TIMEOUT"
    CERT_FAILURES=$((CERT_FAILURES+1))
  fi
done
if [ "$CERT_FAILURES" -gt 0 ]; then
  echo ""
  echo "WARN: ${CERT_FAILURES} domain(s) never presented a valid certificate."
  echo "      Diagnose with: docker logs nginx-ssl-companion"
  echo "      Common causes: DNS not propagated yet, port 80 blocked,"
  echo "      or Let's Encrypt rate limits on duckdns.org names."
fi

echo "=========================================================="
echo " DEPLOYED."
echo "   Dashboard : https://${AI_DOMAIN}"
echo "   API       : https://${API_DOMAIN}/v1  (Bearer <client key>)"
if [[ "$INSTALL_LC" =~ ^[Yy]$ ]]; then
echo "   LibreChat : https://${DUCK_LC}.duckdns.org"
fi
echo "   Ingest    : drop files into /opt/ai-stack/ingest/inbox/"
echo ""
echo " Your 5 client API keys (also saved to ${KEYS_FILE}):"
cat "$KEYS_FILE"
echo ""
echo " Revoke a key: delete its line in nginx-conf/api-keys.conf, then:"
echo "   docker exec nginx-proxy nginx -s reload"
echo "=========================================================="
