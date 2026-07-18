# Multi-Agent AI Stack (LibreChat + Hermes Core AI Engine)

A streamlined, self-hosted AI orchestrator optimized to run efficiently on low-resource virtual private servers (such as a **Hetzner CPX11** with 2 vCPUs, 4 GB RAM, and dual-stack IPv4/IPv6 networking).

This stack links the **Hermes AI Engine Agent** straight into **LibreChat** as an OpenAI-compatible endpoint, alongside **SearXNG** for real-time web browsing and **pgvector/PostgreSQL** for RAG capabilities. It strips away heavy frontend dependencies (`open-webui`) and local inference engines (`whisper-server`) to keep memory consumption low.

## 🚀 Architecture Highlights

* **LibreChat Frontend**: The universal hub for interacting with LLMs and managing agent prompts.
* **Hermes Core AI Engine**: Built-in browser/CDP navigation and tools routed out securely via standard protocols.
* **SearXNG & Scraper**: Self-hosted, privacy-respecting metasearch provider using lightweight Python scraping engines.
* **Zero Hardcoded Secrets**: Fully abstracted `.env` variables ensuring safe tracking via public git structures.
* **Dual-Stack Ready**: Tailored to handle incoming IPv4 and native IPv6 traffic seamlessly.
* **Low-RAM Profiling**: Configured with database engine cache limits (`wiredTigerCacheSizeGB 0.5`) and automated virtual memory expansion (Swap) to run continuously on 4GB VPS servers without crashing.

---

## 🔒 Step 1: Generate & Configure SSH Security

Before provisioning your server, you must use an SSH key instead of a password. This completely stops automated botnets from brute-forcing your root login credentials once your domain is active.

1. Open your local machine terminal and generate a highly secure Ed25519 keypair:
   ```bash
   ssh-keygen -t ed25519 -C "your-email@provider.com"
   ```
2. Accept the default save location. We highly recommend adding a strong passphrase to encrypt the file on your local disk.
3. View and copy your complete **public** key string:
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
4. Log into your cloud host panel (e.g., Hetzner Cloud Console), navigate to **Key Management**, and add this public string. Select this key whenever launching a new instance.

---

## 🌐 Step 2: One-Time DNS Configuration (AWS Route 53)

This deployment uses a free, automated dynamic DNS broker (DuckDNS) to ensure cross-cloud compatibility. Follow these steps to map your AWS managed domain cleanly:

1. Head to [DuckDNS.org](https://duckdns.org) and log in (completely free).
2. Create a unique subdomain (e.g., `my-hermes-stack`). Note down your **Subdomain** and your **Token**.
3. Log into your **AWS Route 53 Console** and open your Hosted Zone (e.g., `enabled.world`).
4. Click **Create Record** and use the following parameters to support **IPv4** traffic:
   * **Record Name:** `ai` (creating `ai.enabled.world`)
   * **Record Type:** `CNAME`
   * **Value:** `my-hermes-stack.duckdns.org` (replace with your actual DuckDNS subdomain)
   * **TTL:** `300` seconds
5. **(Optional IPv6 Support)**: To allow users to connect natively over IPv6, create an additional record alongside your CNAME:
   * **Record Name:** `ai`
   * **Record Type:** `AAAA`
   * **Value:** Paste your Hetzner VPS's static global IPv6 address (found under the server networking tab in your Hetzner console).
   * **TTL:** `300` seconds

---

## ⚡ Option A: Instant Deployment via Cloud-Init (Recommended)

Cloud-Init is supported natively by **Hetzner, DigitalOcean, Linode, AWS, and GCP**. It provisions your server automatically from scratch.

### Deployment Steps:
1. Log into your cloud host console.
2. Spin up a new Server (Minimum required: **Ubuntu 22.04 LTS / 24.04 LTS**). Select your configured SSH key.
3. Expand the **User Data / Cloud-Init** option and paste the entire contents of the `cloud-config.yaml` file from this repository.
4. Launch the server.

### 💽 Hard Drive & Block Storage Volume Configuration
This configuration expects an external **Hetzner Volume** to be attached to your instance during creation. 

The setup initialization sequence automatically formats the storage block as an encrypted or native `ext4` partition, mounts it under `/mnt/ai-volume`, and maps all vector index tables and database operations onto it to preserve your local OS disk space.

### Finishing Configuration:
Once the system state transitions to active, SSH directly into your server. You will be greeted with an interactive system configuration banner. Run:

```bash
sudo configure-ai
```

This script will prompt you for your root domain, email address, OpenRouter API key, and DuckDNS metadata. It dynamically links your Hetzner VPS IP to your DuckDNS alias, provisions free automated SSL certificates via Let's Encrypt, and fires up the container cluster.

---

## 🛠️ Option B: Manual Installation (Standard Bash Setup)

If your host platform doesn't support cloud-config, you can manually clone and initialize this directory on any fresh Ubuntu installation.

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

For reference, an environment parameter template file is detailed below. **Do not modify or commit this version directly inside your git tracking blocks.**

```ini
# .env Configuration Guide
LIBRECHAT_DOMAIN=://yourdomain.com
LETSENCRYPT_EMAIL=your-email@provider.com
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxxxxxxxxxxxxx
DUCKDNS_SUBDOMAIN=your-custom-subdomain
DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

## 🔄 Maintaining & Updating the Stack

To pull down the latest image variants or restart operational components without losing user database structures:

```bash
cd /opt/ai-stack
sudo docker compose down
sudo docker compose pull
sudo docker compose --env-file .env up -d
```

## 🔒 Security Post-Install Recommendations
* **User Registrations**: By default, `ALLOW_REGISTRATION=true` is enabled in `docker-compose.yml` to let you create your initial administrative user account. Once your account is configured, update this value to `false` and rebuild the container cluster (`docker compose up -d`) to lock down registrations.
* **Internal Routing Token Authentication**: The `configure-ai` utility automatically handles generating localized random high-entropy alphanumeric strings for MongoDB and pgvector backends securely on the fly.

---

## 💰 How to Pause the Stack to Save Money (Snapshot & Delete)

Because Hetzner charges for a VPS even when it is turned off, you can use the **Snapshot + External Volume** approach to drop your server billing costs to zero when you aren't using the stack.

### 🛑 To Pause and Stop Billing:
1. SSH into your Hetzner VPS.
2. Run the safe shutdown script to flush databases and detach your hard disk:
   ```bash
   sudo /opt/ai-stack/safeshut.sh
   ```
3. Log into the **Hetzner Cloud Console**.
4. Navigate to your server ➔ **Snapshots** ➔ Click **Take Snapshot**. (This saves your base setup image).
5. Navigate to **Volumes** and explicitly click **Detach** on your volume if it hasn't unlinked yet.
6. Go back to your Server ➔ Click **Delete**. **(Your billing for the computing server drops to zero immediately. You only pay a few cents per month for the volume and snapshot storage.)**

### 🚀 To Resume and Restore Everything:
1. Go to **Hetzner Cloud Console** ➔ Click **Add Server**.
2. For **Image**, click the **Snapshots** tab and select your saved system image.
3. Under the **Volumes** section, check the box next to your existing detached volume to reattach it.
4. Launch the server.
5. Because our Cloud-Init template contains non-destructive loops, your server will automatically re-mount the drive on boot. Your domains, accounts, chats, and vectors will pop straight back online exactly where you left them!

