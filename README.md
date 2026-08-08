# Hermes-First AI Stack (LibreChat optional)

A self-hosted AI agent stack sized for a low-resource VPS (e.g. **Hetzner CPX11**:
2 vCPU, 4 GB RAM, dual-stack IPv4/IPv6).

**Hermes AI Engine** is the core of this deployment: it owns the public domains,
exposes an OpenAI-compatible API to the internet (gated by issued client keys),
and gets retrieval over your own documents via a **folder-drop RAG pipeline with
scanned-PDF OCR**. **LibreChat** is an optional web frontend, enabled with a
single prompt at setup time.

## Architecture

| Component                    | Role                                                             | Exposure                        |
| ---------------------------- | ---------------------------------------------------------------- | ------------------------------- |
| Hermes                       | Agent engine: dashboard (9119) + OpenAI-compatible API (8642)    | Public via nginx vhosts         |
| nginx-proxy + acme-companion | TLS termination, auto Let's Encrypt, **API key gate**            | Ports 80/443 only               |
| rag_api + pgvector           | Vector store & retrieval (standalone — no LibreChat needed)      | Internal                        |
| rag-ingest                   | Watches `ingest/inbox/`, OCRs scans (ocrmypdf/Tesseract), embeds | Internal, RAM-capped            |
| SearXNG + browserless Chrome | Web search & browsing for the agent                              | Internal                        |
| LibreChat + MongoDB          | Optional chat frontend                                           | Public vhost, **profile-gated** |

### Domains — one DuckDNS subdomain per vhost

| Subdomain                 | Serves                      | Auth                         |
| ------------------------- | --------------------------- | ---------------------------- |
| `<name>.duckdns.org`      | Hermes dashboard            | basic auth (set at setup)    |
| `<name>-api.duckdns.org`  | Hermes API (`/v1/...`)      | one of **5 client API keys** |
| `<name>-chat.duckdns.org` | LibreChat (only if enabled) | LibreChat accounts           |

All subdomains are updated at DuckDNS in a single API call, and a cron job
refreshes them every 5 minutes. Each vhost gets its own Let's Encrypt
certificate automatically.

### How the 5 API keys work

Hermes' API server accepts exactly one internal token (`API_SERVER_KEY`).
The setup script issues **5 client keys** (`hk-...`) and installs an nginx
`map`: requests to the API vhost must present one of the 5 keys, which nginx
validates and **swaps for the internal token** before proxying to Hermes.
Clients never see the internal token; you get per-key revocation and per-key
access logs.

```bash
curl https://<name>-api.duckdns.org/v1/chat/completions \
  -H "Authorization: Bearer hk-your-client-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"hello"}]}'
```

Keys live in `/opt/ai-stack/api-keys.txt` (chmod 600). To revoke one, delete
its line in `nginx-conf/api-keys.conf` and run
`docker exec nginx-proxy nginx -s reload`.

### Folder-drop document ingestion (RAG + OCR)

Drop files into `/opt/ai-stack/ingest/inbox/` (scp, rsync, sftp — anything):

- **Digital PDFs / office docs / text** (pdf, docx, pptx, xlsx, txt, md, csv,
  html, epub...) are embedded directly.
- **Scanned PDFs and image scans** (jpg, png, tiff...) are OCR'd first with
  `ocrmypdf` (`--skip-text`: only pages lacking a text layer are processed),
  then embedded.

Files move to `processed/` on success or `failed/` on error; duplicates are
skipped via SHA-256. The ingest container is capped at 1.2 GB RAM and low CPU
priority, so OCR bursts never starve the agent. Everything lands in pgvector
under a shared collection Hermes can query. Set `OCR_LANGUAGES` in `.env`
(e.g. `eng+deu`) and add matching Tesseract packs in `ingest-image/Dockerfile`.

---

## Step 1: SSH key

```bash
ssh-keygen -t ed25519 -C "your-email@provider.com"
cat ~/.ssh/id_ed25519.pub
```

Add the public key in your cloud host panel and select it when creating servers.

## Step 2: DuckDNS

Create **two** subdomains at [DuckDNS.org](https://duckdns.org) (three if you
want LibreChat), e.g. `my-hermes`, `my-hermes-api`, `my-hermes-chat`. Note your
token. Optionally CNAME your own domains at them (e.g. in Route 53); AAAA
records for native IPv6 work as before.

## Option A: Cloud-Init (recommended)

1. Create a server (Ubuntu 22.04/24.04 LTS), select your SSH key, optionally
   attach a block volume.
2. Paste the contents of `cloud-config.yaml` into User Data. Launch.
3. SSH in and run:

```bash
sudo configure-ai
```

The wizard asks for your DuckDNS subdomains and token, email, OpenRouter key,
a dashboard password, and whether to install LibreChat. It then generates all
secrets and the 5 client keys, starts the stack, configures dashboard basic
auth, installs the DNS-refresh cron, and **blocks until every domain serves a
valid HTTPS certificate** before printing your keys and URLs.

## Option B: Manual install

```bash
mkdir -p /opt/ai-stack && cd /opt/ai-stack
curl -sSL https://raw.githubusercontent.com/QuickFactory/ai-deployment/main/deploy.sh -o deploy.sh
chmod +x deploy.sh
sudo ./deploy.sh
```

Same prompts, same result.

## Enabling / disabling LibreChat later

LibreChat (and its MongoDB) exist behind a Compose profile. To toggle:

```bash
cd /opt/ai-stack
# enable: add to .env ->  COMPOSE_PROFILES=librechat  (+ LIBRECHAT_DOMAIN and JWT secrets)
# disable: remove/comment that line
sudo docker compose --env-file .env up -d --remove-orphans
```

Skipping LibreChat also skips MongoDB entirely — a significant RAM saving on a
4 GB box.

## Maintaining & updating

```bash
cd /opt/ai-stack
sudo docker compose down
sudo docker compose pull
sudo docker compose --env-file .env up -d --build
```

## Security notes

- Only ports **80/443** are published. Browserless Chrome, SearXNG, rag_api,
  Postgres and Mongo are reachable solely on the internal Docker network.
- The API vhost rejects requests without a valid client key at the nginx edge;
  Hermes' internal token never leaves the server. Remember the API grants full
  agent access (tools, files, memory) — treat client keys like passwords.
- The dashboard is protected by basic auth set during `configure-ai`.
- If LibreChat is enabled: `ALLOW_REGISTRATION=true` by default so you can
  create the first account — set it to `false` afterwards and re-run
  `docker compose up -d`.

## Pausing to save money (Snapshot & Delete)

Unchanged from before: `sudo /opt/ai-stack/safeshut.sh`, snapshot the server,
detach the volume, delete the server. On restore, boot from the snapshot with
the volume reattached — accounts, vectors **and your ingested document corpus**
(which lives on the volume) come straight back.
