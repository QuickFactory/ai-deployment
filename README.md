# Multi-Agent AI Stack (LibreChat + Hermes Core AI Engine)

A streamlined, self-hosted AI orchestrator optimized to run efficiently on low-resource virtual private servers (such as a **Hetzner CPX11** with 2 vCPUs and 4 GB RAM).

This stack links the **Hermes AI Engine Agent** straight into **LibreChat** as an OpenAI-compatible endpoint, alongside **SearXNG** for real-time web browsing and **pgvector/PostgreSQL** for RAG capabilities. It strips away heavy frontend dependencies (`open-webui`) and local inference engines (`whisper-server`) to keep memory consumption low.

## 🚀 Architecture Highlights

* **LibreChat Frontend**: The universal hub for interacting with LLMs and managing agent prompts.
* **Hermes Core AI Engine**: Built-in browser/CDP navigation and tools routed out securely via standard protocols.
* **SearXNG & Scraper**: Self-hosted, privacy-respecting metasearch provider using lightweight python scraping engines.
* **Zero Hardcoded Secrets**: Fully abstracted `.env` variables ensuring safe tracking via public git structures.
* **Low-RAM Profiling**: Configured with database engine cache limits (`wiredTigerCacheSizeGB 0.5`) and automated virtual memory memory expansion (Swap) to run continuously on 4GB VPS servers without crashing.

---

## ⚡ Option 1: Instant Deployment via Cloud-Init (Recommended)

Cloud-Init is supported natively by **Hetzner, DigitalOcean, Linode, AWS, and GCP**. It provisions your server automatically from scratch.

### Deployment Steps:
1. Log into your cloud host console (e.g., [Hetzner Cloud Console](https://hetzner.cloud)).
2. Spin up a new Server (Minimum required: **Ubuntu 22.04 LTS / 24.04 LTS**).
3. Expand the **User Data / Cloud-Init** option and paste the entire contents of the `cloud-config.yaml` file from this repository.
4. Launch the server.

### Finishing Configuration:
Once the system state transitions to active, SSH directly into your server. You will be greeted with an interactive system configuration banner. Run:

```bash
sudo configure-ai
```

This script will prompt you for your domain name, email address, and OpenRouter API key. It dynamically builds your local production profile, provisions free automated SSL certificates via Let's Encrypt, and fires up the container cluster.

---

## 🛠️ Option 2: Manual Installation (Standard Bash Bash Setup)

If your host platform doesn't support cloud-config, you can manually clone and initialize this tracking directory on any fresh Ubuntu installation.

```bash
# 1. Access the server workspace
mkdir -p /opt/ai-stack && cd /opt/ai-stack

# 2. Clone or download configuration scripts
curl -sSL "https://githubusercontent.com" -o docker-compose.yml
curl -sSL "https://githubusercontent.com" -o librechat.yaml
curl -sSL "https://githubusercontent.com" -o deploy.sh

# 3. Make execution components executable and run
chmod +x deploy.sh
sudo ./deploy.sh
```

---

## 📋 Initial Post-Deployment Configuration

### Network Routing Requirement
Ensure your server public IPv4 addresses are explicitly linked to your target system parameters inside your Domain DNS Manager records:
* `://yourdomain.com` ➔ Point an **A Record** to your VPS Public IP address.

### File Manifest Reference
For reference, an environment parameter template file is detailed below. **Do not modify this version directly inside git tracking blocks.**

```ini
# .env Configuration Guide
LIBRECHAT_DOMAIN=://yourdomain.com
LETSENCRYPT_EMAIL=your-email@provider.com
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxx
```

---

### 🌐 One-Time DNS Routing Configuration (AWS Route 53)

Because this deployment script uses a free, automated dynamic DNS broker (DuckDNS) to ensure cross-cloud compatibility, you must point your AWS managed domain to your DuckDNS alias.

1. Head to [DuckDNS.org](https://duckdns.org) and log in (completely free).
2. Create a unique subdomain (e.g., `my-hermes-stack`). Note down your **Subdomain** and your **Token**.
3. Log into your **AWS Route 53 Console** and open your Hosted Zone (e.g., `enabled.world`).
4. Click **Create Record** and use the following parameters:
   * **Record Name:** `ai` (creating `ai.enabled.world`)
   * **Record Type:** `CNAME`
   * **Value:** `my-hermes-stack.duckdns.org` (replace with your actual DuckDNS subdomain)
   * **TTL:** `300` seconds
5. Save the record.

When you run `sudo configure-ai` on your server, the script automatically pings DuckDNS, linking your Hetzner VPS IP to that alias. AWS Route 53 will automatically resolve your main domain flawlessly!

---

## 🔄 Maintaining & Updating the Stack

To pull down the latest image variants or restart operational components without losing user database structures:

```bash
cd /opt/ai-stack
sudo docker compose down
sudo docker compose pull
sudo docker compose --env-file .env up -d
```

## 🔒 Security Best Practices
* **User Registrations**: By default, `ALLOW_REGISTRATION=true` is enabled in `docker-compose.yml` to let you create your initial administrative user account. Once your account is configured, update this value to `false` and rebuild the container cluster (`docker compose up -d`) to lock down registrations.
* **Internal Routing Token Authentication**: The `configure-ai` utility automatically handles generating localized random high-entropy alphanumeric strings for MongoDB and pgvector backends securely on the fly.
