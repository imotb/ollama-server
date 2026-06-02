#!/bin/bash
set -euo pipefail

# =============================================================================
# Ollama Stack Installer (Ollama + WebUI + Traefik + Dozzle)
# Optimized for Ubuntu 22.04
# Auth method: OpenSSL (No apache2-utils dependency)
# Features: IP Whitelist for API, SSL, Monitoring
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global Variables for API Restriction
API_RESTRICT_ENABLED="false"
API_ALLOWED_IP=""

# Helper Functions
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   Ollama Stack Installer (Ollama + WebUI + Traefik)      ║"
    echo "║                  with Dozzle Monitoring                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root (sudo).${NC}"
        exit 1
    fi
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker is not installed. Installing Docker...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}✓ Docker installed successfully.${NC}"
    else
        echo -e "${GREEN}✓ Docker is already installed.${NC}"
    fi

    # Install docker-compose plugin if missing
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Docker Compose plugin is missing. Installing...${NC}"
        apt-get update && apt-get install -y docker-compose-plugin
    fi
}

get_user_input() {
    echo -e "${BLUE}Please enter the configuration details:${NC}"
    
    # 1. Main Domain
    read -p "Main domain for OpenWebUI (e.g., ai.example.com): " MAIN_DOMAIN
    MAIN_DOMAIN=${MAIN_DOMAIN:-ollama.local}
    
    # 2. API Domain
    DEFAULT_API="api.$MAIN_DOMAIN"
    read -p "Domain for Ollama API [default: $DEFAULT_API]: " API_DOMAIN
    API_DOMAIN=${API_DOMAIN:-$DEFAULT_API}

    # 3. Dozzle Domain (Monitoring)
    DEFAULT_MONITOR="monitor.$MAIN_DOMAIN"
    read -p "Domain for Dozzle Monitoring [default: $DEFAULT_MONITOR]: " MONITOR_DOMAIN
    MONITOR_DOMAIN=${MONITOR_DOMAIN:-$DEFAULT_MONITOR}

    # 4. Traefik Dashboard Domain
    DEFAULT_TRAEFIK="traefik.$MAIN_DOMAIN"
    read -p "Domain for Traefik Dashboard [default: $DEFAULT_TRAEFIK]: " TRAEFIK_DOMAIN
    TRAEFIK_DOMAIN=${TRAEFIK_DOMAIN:-$DEFAULT_TRAEFIK}

    # 5. Email for SSL
    EMAIL=""
    while [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; do
        read -p "Your email for Let's Encrypt (SSL): " EMAIL
        if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            echo -e "${RED}Invalid email format. Please try again.${NC}"
        fi
    done

    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e " Main Domain     : ${CYAN}$MAIN_DOMAIN${NC}"
    echo -e " API Domain      : ${CYAN}$API_DOMAIN${NC}"
    echo -e " Monitor Domain  : ${CYAN}$MONITOR_DOMAIN${NC}"
    echo -e " Traefik Domain  : ${CYAN}$TRAEFIK_DOMAIN${NC}"
    echo -e " Email           : ${CYAN}$EMAIL${NC}"
    echo -e "${GREEN}----------------------------------------${NC}"
    
    read -p "Confirm configuration? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo -e "${RED}Operation cancelled by user.${NC}"
        exit 0
    fi
}

configure_security() {
    if command -v ufw &> /dev/null; then
        echo -e "${YELLOW}UFW firewall detected.${NC}"
        read -p "Do you want to allow ports 80, 443, and 8080 in UFW? (y/n): " FW_CONFIRM
        if [[ "$FW_CONFIRM" == "y" || "$FW_CONFIRM" == "Y" ]]; then
            ufw allow 80/tcp comment 'Traefik Web' || echo -e "${YELLOW}Warning: could not add UFW rule for port 80.${NC}"
            ufw allow 443/tcp comment 'Traefik WebSecure' || echo -e "${YELLOW}Warning: could not add UFW rule for port 443.${NC}"
            ufw allow 8080/tcp comment 'Traefik Dashboard Direct' || echo -e "${YELLOW}Warning: could not add UFW rule for port 8080.${NC}"
            echo -e "${GREEN}✓ Firewall rules updated.${NC}"
            echo -e "${YELLOW}Note: If UFW is inactive, run 'sudo ufw enable' to activate it.${NC}"
        fi
    else
        echo -e "${YELLOW}UFW not found. Skipping firewall configuration.${NC}"
    fi

    echo -e "${BLUE}API Security Configuration${NC}"
    read -p "Do you want to restrict API access ($API_DOMAIN) to a specific IP? (y/n): " API_RESTRICT_CONFIRM
    if [[ "$API_RESTRICT_CONFIRM" == "y" || "$API_RESTRICT_CONFIRM" == "Y" ]]; then
        read -p "Enter the allowed IP address (e.g., 1.2.3.4): " API_ALLOWED_IP
        # Simple IP validation (IPv4)
        if [[ "$API_ALLOWED_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            API_RESTRICT_ENABLED="true"
            echo -e "${GREEN}✓ API will be restricted to ${CYAN}$API_ALLOWED_IP${NC}"
        else
            echo -e "${RED}Invalid IP format. Skipping restriction.${NC}"
            API_RESTRICT_ENABLED="false"
            API_ALLOWED_IP=""
        fi
    fi
}

generate_auth() {
    echo -e "${YELLOW}Generating Secure Credentials (OpenSSL Method)...${NC}"
    
    # 1. Generate Traefik Password (Base64 style)
    TRAEFIK_USER="admin"
    TRAEFIK_PASS=$(openssl rand -base64 16)
    TRAEFIK_HASH=$(echo "$TRAEFIK_PASS" | openssl passwd -apr1 -stdin | sed -e 's/\$/\$\$/g')
    TRAEFIK_AUTH="${TRAEFIK_USER}:${TRAEFIK_HASH}"
    
    # 2. Generate Dozzle Password (Alphanumeric style, matching ztmaster logic)
    DOZZLE_USER="admin"
    DOZZLE_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    DOZZLE_HASH=$(echo "$DOZZLE_PASS" | openssl passwd -apr1 -stdin | sed -e 's/\$/\$\$/g')
    DOZZLE_AUTH="${DOZZLE_USER}:${DOZZLE_HASH}"
    
    echo -e "${GREEN}✓ Credentials generated successfully.${NC}"
}

create_project_structure() {
    DIR="ollama-stack"
    if [ -d "$DIR" ]; then
        echo -e "${YELLOW}Directory '$DIR' already exists.${NC}"
        read -p "Remove and recreate it? All existing files will be deleted. (y/n): " RECREATE
        if [[ "$RECREATE" != "y" && "$RECREATE" != "Y" ]]; then
            echo -e "${RED}Operation cancelled by user.${NC}"
            exit 0
        fi
        rm -rf "$DIR"
    fi
    mkdir -p "$DIR"
    cd "$DIR" || { echo -e "${RED}Failed to enter directory '$DIR'. Aborting.${NC}"; exit 1; }
    echo -e "${GREEN}✓ Project directory created.${NC}"
}

create_env_file() {
    cat > .env << EOF
DOMAIN=$MAIN_DOMAIN
API_DOMAIN=$API_DOMAIN
MONITOR_DOMAIN=$MONITOR_DOMAIN
TRAEFIK_DOMAIN=$TRAEFIK_DOMAIN
EMAIL=$EMAIL
TRAEFIK_AUTH=$TRAEFIK_AUTH
DOZZLE_AUTH=$DOZZLE_AUTH
OLLAMA_HOST=0.0.0.0
API_ALLOWED_IP=$API_ALLOWED_IP
EOF
    echo -e "${GREEN}✓ .env file created.${NC}"
}

create_docker_compose() {
    # Prepare label content strings (without leading spaces/dashes)
    API_IP_CONTENT="traefik.http.middlewares.api-ipwhitelist.ipallowlist.sourcerange=\${API_ALLOWED_IP}"
    OLLAMA_MW_CONTENT="traefik.http.routers.ollama.middlewares=api-ipwhitelist"

    if [ "$API_RESTRICT_ENABLED" = "true" ]; then
        # Create lines with exactly 6 spaces indent to match YAML structure
        LINE_IP_WHITELIST="     - \"${API_IP_CONTENT}\""
        LINE_OLLAMA_MW="     - \"${OLLAMA_MW_CONTENT}\""
    else
        LINE_IP_WHITELIST="      # API IP Restriction Disabled"
        LINE_OLLAMA_MW="      # No IP restriction for API"
    fi

    cat > docker-compose.yml << EOF
services:
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Traefik Dashboard
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --certificatesresolvers.myresolver.acme.tlschallenge=true
      - --certificatesresolvers.myresolver.acme.email=\${EMAIL}
      - --certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik-net
    labels:
      # Traefik Dashboard Auth Middleware
      - "traefik.http.middlewares.traefik-auth.basicauth.users=\${TRAEFIK_AUTH}"
      # API IP Whitelist Middleware (Defined here, used by Ollama)
 ${LINE_IP_WHITELIST}
      # Traefik Dashboard Configuration
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`\${TRAEFIK_DOMAIN}\`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls.certresolver=myresolver"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=traefik-auth"

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    environment:
      - OLLAMA_HOST=0.0.0.0
    volumes:
      - ollama:/root/.ollama
    ports:
      - "11434:11434"
    networks:
      - traefik-net
    labels:
      - traefik.enable=true
      - traefik.http.routers.ollama.rule=Host(\`\${API_DOMAIN}\`)
      - traefik.http.routers.ollama.entrypoints=websecure
      - traefik.http.routers.ollama.tls.certresolver=myresolver
      - traefik.http.services.ollama.loadbalancer.server.port=11434
      # Apply IP Whitelist to API if enabled
 ${LINE_OLLAMA_MW}

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    volumes:
      - openwebui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
    networks:
      - traefik-net
    labels:
      - traefik.enable=true
      - traefik.http.routers.webui.rule=Host(\`\${DOMAIN}\`)
      - traefik.http.routers.webui.entrypoints=websecure
      - traefik.http.routers.webui.tls.certresolver=myresolver
      - traefik.http.services.webui.loadbalancer.server.port=8080

  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - traefik-net
    labels:
      - traefik.enable=true
      # Dozzle Auth Middleware (Separate from Traefik)
      - "traefik.http.middlewares.dozzle-auth.basicauth.users=\${DOZZLE_AUTH}"
      # Dozzle Configuration
      - "traefik.http.routers.dozzle.rule=Host(\`\${MONITOR_DOMAIN}\`)"
      - "traefik.http.routers.dozzle.entrypoints=websecure"
      - "traefik.http.routers.dozzle.tls.certresolver=myresolver"
      - "traefik.http.services.dozzle.loadbalancer.server.port=8080"
      - "traefik.http.routers.dozzle.middlewares=dozzle-auth"

networks:
  traefik-net:
    driver: bridge

volumes:
  ollama:
  openwebui:
EOF
    echo -e "${GREEN}✓ docker-compose.yml created.${NC}"
}

run_containers() {
    echo -e "${YELLOW}Starting Docker Compose...${NC}"
    docker network create traefik-net 2>/dev/null || true
    if ! docker compose up -d; then
        echo -e "${RED}✗ Failed to start containers. Check the logs above or run 'docker compose logs' manually.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Containers started successfully.${NC}"
}

install_model() {
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "Would you like to install a model now?"
    echo "Select an option:"
    echo "1) deepseek-r1:8b"
    echo "2) ministral-3:8b"
    echo "3) gpt-oss:20b"
    echo "4) Skip model installation"
    echo -e "${BLUE}----------------------------------------${NC}"
    read -p "Enter choice (1-4): " MODEL_CHOICE || MODEL_CHOICE=""

    case "${MODEL_CHOICE}" in
        1) MODEL_NAME="deepseek-r1:8b" ;;
        2) MODEL_NAME="ministral-3:8b" ;;
        3) MODEL_NAME="gpt-oss:20b" ;;
        *)
            echo -e "${YELLOW}Skipping model installation.${NC}"
            MODEL_NAME=""
            ;;
    esac

    if [ -n "${MODEL_NAME}" ]; then
        echo -e "${YELLOW}Pulling ${MODEL_NAME}... (This may take a few minutes)${NC}"
        if docker exec -it ollama ollama pull "${MODEL_NAME}"; then
            echo -e "${GREEN}✓ Model ${MODEL_NAME} installed successfully.${NC}"
        else
            echo -e "${RED}✗ Failed to install model. Check logs later.${NC}"
        fi
    fi
}

show_info() {
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "Dashboard (OpenWebUI) : ${CYAN}https://${MAIN_DOMAIN}${NC}"
    echo -e "API (Ollama)           : ${CYAN}https://${API_DOMAIN}${NC}"
    
    if [ "$API_RESTRICT_ENABLED" = "true" ]; then
        echo -e "                        ${RED}[Restricted to IP: ${API_ALLOWED_IP}]${NC}"
    else
        echo -e "                        ${GREEN}[Public Access]${NC}"
    fi

    echo -e "Monitoring (Dozzle)    : ${CYAN}https://${MONITOR_DOMAIN}${NC}"
    echo -e "Traefik Dashboard     : ${CYAN}https://${TRAEFIK_DOMAIN}${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e "${RED}!! AUTHENTICATION CREDENTIALS !!${NC}"
    echo -e "${CYAN}1. Traefik Dashboard:${NC}"
    echo -e "   Username: ${GREEN}${TRAEFIK_USER}${NC}"
    echo -e "   Password: ${GREEN}${TRAEFIK_PASS}${NC}"
    echo -e "${CYAN}2. Dozzle Monitoring:${NC}"
    echo -e "   Username: ${GREEN}${DOZZLE_USER}${NC}"
    echo -e "   Password: ${GREEN}${DOZZLE_PASS}${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e "${YELLOW}NOTE: It may take a few minutes for SSL certificates to generate.${NC}"
    echo -e "${YELLOW}For more models, visit: ${CYAN}https://ollama.com/models${NC}"
    echo -e "${YELLOW}To view logs, run:${NC}"
    echo -e "cd ${PWD} && docker compose logs -f"
}

# Main Execution Flow
check_root
print_banner
install_docker
get_user_input
configure_security # This now contains UFW and IP Restriction logic
generate_auth
create_project_structure
create_env_file
create_docker_compose
run_containers
install_model
show_info
