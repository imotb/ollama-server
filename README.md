<div align="center">

# Ollama Stack

**One-command deployment of Ollama + OpenWebUI + Traefik (SSL) + Dozzle Monitoring**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%2022.04-blue)](https://ubuntu.com)
[![Shell](https://img.shields.io/badge/Shell-Bash-green)](setup_ollama_stack.sh)

</div>

---

## What It Does

A single interactive Bash script that provisions a production-ready LLM server stack on Ubuntu 22.04:

| Service | Purpose | Auth |
|---------|---------|------|
| **Ollama** | LLM inference server (REST API) | Optional IP whitelist |
| **OpenWebUI** | ChatGPT-like chat interface | Ollama backend (unauthenticated) |
| **Traefik** | Reverse proxy + automatic Let's Encrypt SSL | Basic auth (dashboard) |
| **Dozzle** | Real-time Docker container logs | Basic auth |

---

## 🚀 Quick Start

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/imotb/ollama-server/main/setup_ollama_stack.sh)"
```

Or manually:

```bash
wget https://raw.githubusercontent.com/imotb/ollama-server/main/setup_ollama_stack.sh
chmod +x setup_ollama_stack.sh
sudo ./setup_ollama_stack.sh
```

---

## What You'll Be Asked

The script prompts you for:

| Prompt | Example | Purpose |
|--------|---------|---------|
| Main domain | `ai.example.com` | OpenWebUI chat interface |
| API domain | `api.ai.example.com` | Ollama REST API endpoint |
| Monitor domain | `monitor.ai.example.com` | Dozzle log viewer |
| Traefik domain | `traefik.ai.example.com` | Traefik dashboard |
| Email | `you@example.com` | Let's Encrypt SSL registration |
| API IP whitelist | `1.2.3.4` | Restrict Ollama API to a single IP (optional) |
| Model | `deepseek-r1:8b` | Pre-install a model (optional) |

All domains get automatic HTTPS via Let's Encrypt (Traefik).

---

## Architecture

```
Internet
   │
   ▼
 ┌──────────┐    ┌───────────────────────────────────────────┐
 │  :80/443 │───▶            Traefik (Proxy)                 │
 └──────────┘    │  ┌─────────────────────────────────────┐   │
                 │  │  Middleware:                        │   │
                 │  │  - SSL termination (Let's Encrypt)  │   │
                 │  │  - Basic auth (dashboard/dozzle)    │   │
                 │  │  - IP whitelist (Ollama API)        │   │
                 │  └─────────────────────────────────────┘   │
                 └────┬──────────┬─────────────┬──────────────┘
                      │          │             │
                      ▼          ▼             ▼
               ┌──────────┐ ┌────────┐ ┌────────────┐
               │ OpenWebUI│ │ Ollama │ │   Dozzle   │
               │  :8080   │ │ :11434 │ │   Logs     │
               └────┬─────┘ └───┬────┘ └────────────┘
                    │           │
                    └─── Sends ─┘
                    inference requests
```

All containers share a `traefik-net` Docker network.

---

## Security

- **SSL everywhere** — automatic Let's Encrypt certificates via Traefik
- **HTTP → HTTPS redirect** — all traffic forced to TLS
- **Basic auth** — Traefik dashboard and Dozzle require credentials (auto-generated)
- **IP whitelist** — optionally restrict the Ollama API endpoint to a single IP address
- **UFW integration** — optionally open only ports 80, 443, and 8080

---

## What Gets Created

```
~/ollama-stack/
├── .env                  # All configuration (domains, credentials, etc.)
├── docker-compose.yml    # Service definitions
├── letsencrypt/          # SSL certificates (auto-managed by Traefik)
```

---

## Post-Installation

After the script finishes, you'll get a summary like:

```
Dashboard (OpenWebUI) : https://ai.example.com
API (Ollama)          : https://api.ai.example.com
Monitoring (Dozzle)   : https://monitor.ai.example.com
Traefik Dashboard     : https://traefik.ai.example.com

!! AUTHENTICATION CREDENTIALS !!
1. Traefik Dashboard:
   Username: admin
   Password: <random>

2. Dozzle Monitoring:
   Username: admin
   Password: <random>
```

> ⚠️ **Save these credentials** — passwords are generated once and not stored outside the `.env` file.

---

## Managing Your Stack

```bash
cd ~/ollama-stack
docker compose logs -f        # View all logs
docker compose ps             # Check container status
docker compose restart <name> # Restart a single service
docker compose down           # Stop everything
docker compose up -d          # Start everything
```

### Pulling Additional Models

```bash
docker exec -it ollama ollama pull llama3.2
docker exec -it ollama ollama pull mistral
```

Browse all available models at [ollama.com/models](https://ollama.com/models).

---

## Prerequisites

- Ubuntu 22.04 (or similar Debian-based distro)
- Root/sudo access
- A domain name with DNS A records pointing to your server's IP
- Ports 80 and 443 reachable from the internet (for Let's Encrypt)

The script installs Docker if missing.

---

## License

[MIT](LICENSE)
