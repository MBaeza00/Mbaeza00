#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║           HOMELAB INSTALLER — 				   ║
# ║      Debian 12 / Ubuntu 24.04 · Docker · Open Source	   ║
# ╚══════════════════════════════════════════════════════════════════╝
# Uso: bash homelab-install.sh
# Requiere: bash 4+, sudo, conexión a internet

set -euo pipefail

# ─── Colores y estilos ────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
ITALIC="\033[3m"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

BG_BLACK="\033[40m"
BG_BLUE="\033[44m"
BG_CYAN="\033[46m"

# ─── Variables globales ───────────────────────────────────────────
HOMELAB_DIR="$HOME/homelab"
LOG_FILE="$HOME/homelab-install.log"
STEPS_TOTAL=0
STEPS_DONE=0

# Configuración (se rellena en el wizard)
HOST_IP=""
HOST_TZ="Europe/Madrid"
DUCKDNS_SUBDOMAIN=""
DUCKDNS_TOKEN=""
PIHOLE_PASS=""
GRAFANA_PASS=""
VW_TOKEN=""
MYSQL_ROOT_PASS=""
MYSQL_PASS=""
WG_PEERS="movil,portatil"

# Qué stacks instalar
INSTALL_BASE=true
INSTALL_MEDIA=false
INSTALL_CLOUD=false
INSTALL_NETWORK=false
INSTALL_DUCKDNS=false

# ─── Utilidades de UI ─────────────────────────────────────────────

clear_screen() { printf "\033[2J\033[H"; }

# Header principal
print_header() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 70)
  local line
  line=$(printf '─%.0s' $(seq 1 "$cols"))

  echo -e "${CYAN}${BOLD}"
  echo "  ██╗  ██╗ ██████╗ ███╗   ███╗███████╗██╗      █████╗ ██████╗ "
  echo "  ██║  ██║██╔═══██╗████╗ ████║██╔════╝██║     ██╔══██╗██╔══██╗"
  echo "  ███████║██║   ██║██╔████╔██║█████╗  ██║     ███████║██████╔╝"
  echo "  ██╔══██║██║   ██║██║╚██╔╝██║██╔══╝  ██║     ██╔══██║██╔══██╗"
  echo "  ██║  ██║╚██████╔╝██║ ╚═╝ ██║███████╗███████╗██║  ██║██████╔╝"
  echo "  ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚═════╝ "
  echo -e "${RESET}"
  echo -e "${DIM}${CYAN}  ${line}${RESET}"
  echo -e "${DIM}  Instalador interactivo · Debian 12 / Ubuntu 24.04 · Docker${RESET}"
  echo -e "${DIM}${CYAN}  ${line}${RESET}"
  echo
}

# Spinner de carga
spinner() {
  local pid=$1
  local msg="${2:-Procesando...}"
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  tput civis 2>/dev/null || true  # ocultar cursor
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}${frames[$i]}${RESET}  ${msg}${DIM}...${RESET}"
    i=$(( (i+1) % ${#frames[@]} ))
    sleep 0.08
  done
  tput cnorm 2>/dev/null || true  # restaurar cursor
  printf "\r"
}

# Barra de progreso
progress_bar() {
  local current=$1
  local total=$2
  local label="${3:-}"
  local width=40
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local pct=$(( current * 100 / total ))

  local bar_filled
  bar_filled=$(printf '█%.0s' $(seq 1 $filled) 2>/dev/null || printf '%0.s█' $(seq 1 $filled))
  local bar_empty
  bar_empty=$(printf '░%.0s' $(seq 1 $empty) 2>/dev/null || printf '%0.s░' $(seq 1 $empty))

  printf "\r  ${CYAN}[${GREEN}${bar_filled}${DIM}${bar_empty}${CYAN}]${RESET} ${BOLD}%3d%%${RESET}  ${DIM}${label}${RESET}" \
    "$pct"
}

# Mensaje de estado con icono
status_ok()   { echo -e "  ${GREEN}✓${RESET}  ${1}"; }
status_err()  { echo -e "  ${RED}✗${RESET}  ${RED}${1}${RESET}"; }
status_warn() { echo -e "  ${YELLOW}⚠${RESET}  ${YELLOW}${1}${RESET}"; }
status_info() { echo -e "  ${CYAN}→${RESET}  ${1}"; }
status_step() { echo -e "\n  ${BG_CYAN}${BLACK} PASO ${1} ${RESET}  ${BOLD}${2}${RESET}"; echo; }

# Separador decorativo
separator() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 70)
  echo -e "${DIM}${CYAN}  $(printf '─%.0s' $(seq 1 $(( cols - 4 )) ))${RESET}"
}

# Cuadro de texto
box() {
  local title="$1"
  local body="$2"
  echo
  echo -e "  ${CYAN}╭─ ${BOLD}${title}${RESET}${CYAN} ─────────────────────────────────────────╮${RESET}"
  while IFS= read -r line; do
    printf "  ${CYAN}│${RESET}  %-52s ${CYAN}│${RESET}\n" "$line"
  done <<< "$body"
  echo -e "  ${CYAN}╰──────────────────────────────────────────────────────╯${RESET}"
  echo
}

# Confirmación sí/no
confirm() {
  local msg="$1"
  local default="${2:-s}"
  local prompt
  if [[ "$default" == "s" ]]; then
    prompt="${GREEN}S${RESET}/${DIM}n${RESET}"
  else
    prompt="${DIM}s${RESET}/${GREEN}N${RESET}"
  fi
  echo -ne "  ${CYAN}?${RESET}  ${msg} [${prompt}]: "
  read -r answer
  answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
  [[ -z "$answer" ]] && answer="$default"
  [[ "$answer" == "s" || "$answer" == "y" || "$answer" == "si" || "$answer" == "yes" ]]
}

# Input con valor por defecto
prompt_input() {
  local label="$1"
  local default="${2:-}"
  local secret="${3:-false}"
  local value

  if [[ -n "$default" ]]; then
    echo -ne "  ${CYAN}›${RESET}  ${label} ${DIM}[${default}]${RESET}: "
  else
    echo -ne "  ${CYAN}›${RESET}  ${label}: "
  fi

  if [[ "$secret" == "true" ]]; then
    read -rs value
    echo
  else
    read -r value
  fi

  if [[ -z "$value" && -n "$default" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Ejecutar comando con spinner y log
run_cmd() {
  local msg="$1"
  shift
  echo -n "  "
  ("$@" >> "$LOG_FILE" 2>&1) &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid"
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    status_ok "$msg"
  else
    status_err "$msg (código: $exit_code)"
    echo -e "  ${DIM}  Ver detalles: ${LOG_FILE}${RESET}"
    return $exit_code
  fi
}

# Pausa con contador
pause() {
  local secs="${1:-3}"
  local msg="${2:-Continuando en}"
  for i in $(seq "$secs" -1 1); do
    printf "\r  ${DIM}${msg} ${CYAN}%d${RESET}${DIM}s...${RESET}   " "$i"
    sleep 1
  done
  printf "\r%60s\r"
}

# ─── SECCIONES DEL INSTALADOR ─────────────────────────────────────

welcome_screen() {
  clear_screen
  print_header

  echo -e "  ${BOLD}Bienvenido al instalador de Homelab.${RESET}"
  echo
  echo -e "  Este script configurará tu portátil como servidor doméstico"
  echo -e "  con Docker y los servicios que elijas."
  echo
  echo -e "  ${YELLOW}${BOLD}Requisitos previos:${RESET}"
  echo -e "  ${DIM}·${RESET}  Debian 12 o Ubuntu Server 24.04 instalado"
  echo -e "  ${DIM}·${RESET}  Acceso sudo"
  echo -e "  ${DIM}·${RESET}  Conexión a internet activa"
  echo -e "  ${DIM}·${RESET}  Al menos 8 GB de RAM recomendados"
  echo
  separator

  # Detectar distro
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    status_info "Sistema detectado: ${BOLD}${PRETTY_NAME}${RESET}"
  fi

  # Detectar RAM
  local ram_gb
  ram_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
  status_info "RAM disponible: ${BOLD}${ram_gb} GB${RESET}"

  # Detectar IP
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  status_info "IP local: ${BOLD}${HOST_IP}${RESET}"

  echo
  if ! confirm "¿Deseas continuar con la instalación?"; then
    echo
    echo -e "  ${DIM}Instalación cancelada.${RESET}"
    echo
    exit 0
  fi
}

menu_stacks() {
  clear_screen
  print_header

  echo -e "  ${BOLD}Selección de stacks a instalar${RESET}"
  echo -e "  ${DIM}El stack base se instala siempre. Elige el resto:${RESET}"
  echo

  # Stack base (siempre)
  echo -e "  ${GREEN}✓${RESET}  ${BOLD}[BASE]${RESET}     Portainer + Nginx Proxy Manager + Watchtower"
  echo -e "  ${DIM}           Gestión Docker, reverse proxy, actualizaciones automáticas${RESET}"
  echo

  # Media
  echo -ne "  ${CYAN}?${RESET}  ${BOLD}[MEDIOS]${RESET}   Jellyfin + Navidrome  "
  echo -e "  ${DIM}(servidor vídeo + música)${RESET}"
  if confirm "     ¿Instalar stack de medios?"; then
    INSTALL_MEDIA=true
    echo -e "  ${GREEN}✓${RESET}  Stack de medios ${GREEN}seleccionado${RESET}"
  else
    echo -e "  ${DIM}✗  Stack de medios omitido${RESET}"
  fi
  echo

  # Cloud
  echo -ne "  ${CYAN}?${RESET}  ${BOLD}[CLOUD]${RESET}    Nextcloud + Vaultwarden  "
  echo -e "  ${DIM}(Drive propio + gestor contraseñas)${RESET}"
  if confirm "     ¿Instalar stack cloud?"; then
    INSTALL_CLOUD=true
    echo -e "  ${GREEN}✓${RESET}  Stack cloud ${GREEN}seleccionado${RESET}"
  else
    echo -e "  ${DIM}✗  Stack cloud omitido${RESET}"
  fi
  echo

  # Network
  echo -ne "  ${CYAN}?${RESET}  ${BOLD}[RED]${RESET}      Pi-hole + WireGuard + Grafana  "
  echo -e "  ${DIM}(DNS, VPN, monitorización)${RESET}"
  if confirm "     ¿Instalar stack de red y seguridad?"; then
    INSTALL_NETWORK=true
    echo -e "  ${GREEN}✓${RESET}  Stack de red ${GREEN}seleccionado${RESET}"
  else
    echo -e "  ${DIM}✗  Stack de red omitido${RESET}"
  fi
  echo

  # DuckDNS
  echo -ne "  ${CYAN}?${RESET}  ${BOLD}[DDNS]${RESET}     DuckDNS  "
  echo -e "  ${DIM}(dominio gratuito con IP dinámica)${RESET}"
  if confirm "     ¿Configurar acceso externo con DuckDNS?"; then
    INSTALL_DUCKDNS=true
    echo -e "  ${GREEN}✓${RESET}  DuckDNS ${GREEN}seleccionado${RESET}"
  else
    echo -e "  ${DIM}✗  DuckDNS omitido${RESET}"
  fi
  echo

  pause 2 "Avanzando en"
}

wizard_config() {
  clear_screen
  print_header

  echo -e "  ${BOLD}Configuración del sistema${RESET}"
  echo -e "  ${DIM}Pulsa Enter para aceptar el valor por defecto entre corchetes.${RESET}"
  echo

  separator
  echo -e "  ${BOLD}Sistema${RESET}"
  echo

  HOST_TZ=$(prompt_input "Zona horaria" "Europe/Madrid")
  HOST_IP=$(prompt_input "IP estática del portátil" "$HOST_IP")

  if [[ "$INSTALL_DUCKDNS" == "true" ]]; then
    echo
    separator
    echo -e "  ${BOLD}DuckDNS${RESET}"
    echo -e "  ${DIM}Regístrate gratis en https://www.duckdns.org si no tienes cuenta.${RESET}"
    echo
    DUCKDNS_SUBDOMAIN=$(prompt_input "Subdominio DuckDNS (sin .duckdns.org)")
    DUCKDNS_TOKEN=$(prompt_input "Token de DuckDNS" "" "true")
  fi

  if [[ "$INSTALL_NETWORK" == "true" ]]; then
    echo
    separator
    echo -e "  ${BOLD}Pi-hole y WireGuard${RESET}"
    echo
    PIHOLE_PASS=$(prompt_input "Contraseña para Pi-hole web" "" "true")
    WG_PEERS=$(prompt_input "Clientes WireGuard" "movil,portatil")
    GRAFANA_PASS=$(prompt_input "Contraseña Grafana" "" "true")
  fi

  if [[ "$INSTALL_CLOUD" == "true" ]]; then
    echo
    separator
    echo -e "  ${BOLD}Nextcloud y Vaultwarden${RESET}"
    echo
    MYSQL_ROOT_PASS=$(prompt_input "Contraseña root MariaDB" "" "true")
    MYSQL_PASS=$(prompt_input "Contraseña usuario MariaDB" "" "true")
    VW_TOKEN=$(openssl rand -base64 48 2>/dev/null || date +%s | sha256sum | base64 | head -c 48)
    status_info "Token Vaultwarden generado automáticamente ${DIM}(guardado en ${LOG_FILE})${RESET}"
    echo "VAULTWARDEN_ADMIN_TOKEN=$VW_TOKEN" >> "$LOG_FILE"
  fi

  echo
  separator
  echo
  echo -e "  ${BOLD}Resumen de configuración:${RESET}"
  echo
  echo -e "  ${DIM}IP del servidor:${RESET}    ${BOLD}${HOST_IP}${RESET}"
  echo -e "  ${DIM}Zona horaria:${RESET}       ${BOLD}${HOST_TZ}${RESET}"
  [[ "$INSTALL_DUCKDNS" == "true" ]] && \
    echo -e "  ${DIM}Dominio:${RESET}            ${BOLD}${DUCKDNS_SUBDOMAIN}.duckdns.org${RESET}"
  echo -e "  ${DIM}Stacks:${RESET}             ${BOLD}Base${RESET} $(${INSTALL_MEDIA} && echo "+ Medios") $(${INSTALL_CLOUD} && echo "+ Cloud") $(${INSTALL_NETWORK} && echo "+ Red") $(${INSTALL_DUCKDNS} && echo "+ DuckDNS") 2>/dev/null || true"
  echo

  if ! confirm "¿Confirmar y comenzar instalación?"; then
    echo
    status_warn "Volviendo al menú de stacks..."
    sleep 1
    menu_stacks
    wizard_config
  fi
}

# ─── INSTALACIÓN: SISTEMA BASE ────────────────────────────────────

install_system() {
  clear_screen
  print_header
  status_step "1/$(count_steps)" "Preparar sistema operativo"

  run_cmd "Actualizando lista de paquetes" sudo apt-get update -q
  run_cmd "Actualizando paquetes instalados" sudo apt-get upgrade -y -q
  run_cmd "Instalando herramientas base" \
    sudo apt-get install -y -q curl wget git htop nano ufw fail2ban ca-certificates gnupg lsb-release

  # Tapa cerrada
  status_info "Configurando tapa cerrada..."
  sudo sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
  sudo sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
  if ! grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf; then
    echo -e "\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore" | \
      sudo tee -a /etc/systemd/logind.conf > /dev/null
  fi
  run_cmd "Aplicando configuración de tapa" sudo systemctl restart systemd-logind

  # Firewall
  run_cmd "Configurando UFW (firewall)" bash -c "sudo ufw --force enable && sudo ufw allow OpenSSH"

  # TLP
  run_cmd "Instalando TLP (gestión de energía)" sudo apt-get install -y -q tlp tlp-rdw
  run_cmd "Habilitando TLP" sudo systemctl enable --now tlp

  # zram
  if sudo apt-get install -y -q zram-tools 2>/dev/null; then
    status_ok "zram instalado"
  fi

  # Crear directorios homelab
  mkdir -p "$HOMELAB_DIR"/{base,media,cloud,network,duckdns,backups}
  status_ok "Estructura de directorios creada en ${BOLD}${HOMELAB_DIR}${RESET}"

  ((STEPS_DONE++))
  echo
  pause 2 "Siguiente paso en"
}

# ─── INSTALACIÓN: DOCKER ──────────────────────────────────────────

install_docker() {
  clear_screen
  print_header
  status_step "2/$(count_steps)" "Instalar Docker Engine"

  # Detectar distro para URL correcta
  local distro
  distro=$(. /etc/os-release && echo "$ID")

  run_cmd "Añadiendo clave GPG de Docker" bash -c "
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${distro}/gpg | \
      sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
  "

  run_cmd "Añadiendo repositorio Docker" bash -c "
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/${distro} \$(lsb_release -cs) stable\" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -q
  "

  run_cmd "Instalando Docker Engine + Compose" \
    sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  run_cmd "Habilitando Docker al inicio" sudo systemctl enable docker

  # Añadir usuario al grupo docker
  local current_user
  current_user=$(whoami)
  run_cmd "Añadiendo ${current_user} al grupo docker" sudo usermod -aG docker "$current_user"

  # Verificación
  local docker_version
  docker_version=$(docker --version 2>/dev/null | grep -oP 'Docker version \K[^,]+' || echo "desconocida")
  status_ok "Docker ${BOLD}${docker_version}${RESET} instalado correctamente"

  echo
  status_warn "Nota: los cambios de grupo se aplican en la próxima sesión SSH."
  echo

  ((STEPS_DONE++))
  pause 2 "Siguiente paso en"
}

# ─── GENERADORES DE COMPOSE ───────────────────────────────────────

generate_base_compose() {
  cat > "$HOMELAB_DIR/base/docker-compose.yml" << EOF
# Stack base — Portainer + Nginx Proxy Manager + Watchtower
# Generado por homelab-install.sh
services:

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    ports:
      - "9443:9443"
      - "8000:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    environment:
      - TZ=${HOST_TZ}

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    environment:
      - TZ=${HOST_TZ}

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - TZ=${HOST_TZ}
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *

volumes:
  portainer_data:
  npm_data:
  npm_letsencrypt:
EOF
}

generate_media_compose() {
  cat > "$HOMELAB_DIR/media/docker-compose.yml" << EOF
# Stack de medios — Jellyfin + Navidrome
services:

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: always
    ports:
      - "8096:8096"
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - \${MEDIA_PATH:-/media}:/media:ro
    environment:
      - TZ=${HOST_TZ}

  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    restart: always
    ports:
      - "4533:4533"
    volumes:
      - navidrome_data:/data
      - \${MUSIC_PATH:-/media/music}:/music:ro
    environment:
      - TZ=${HOST_TZ}
      - ND_SCANSCHEDULE=1h
      - ND_LOGLEVEL=info

volumes:
  jellyfin_config:
  jellyfin_cache:
  navidrome_data:
EOF
}

generate_cloud_compose() {
  cat > "$HOMELAB_DIR/cloud/docker-compose.yml" << EOFC
# Stack cloud — Nextcloud + Vaultwarden
services:

  nextcloud-db:
    image: mariadb:11
    container_name: nextcloud-db
    restart: always
    volumes:
      - nextcloud_db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASS}
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=${MYSQL_PASS}

  nextcloud-redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: always
    volumes:
      - nextcloud_redis:/data

  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: always
    ports:
      - "8080:80"
    depends_on:
      - nextcloud-db
      - nextcloud-redis
    volumes:
      - nextcloud_data:/var/www/html
    environment:
      - TZ=${HOST_TZ}
      - MYSQL_HOST=nextcloud-db
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=${MYSQL_PASS}
      - REDIS_HOST=nextcloud-redis
      - NEXTCLOUD_TRUSTED_DOMAINS=${HOST_IP}

  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: always
    ports:
      - "8888:80"
    volumes:
      - vaultwarden_data:/data
    environment:
      - TZ=${HOST_TZ}
      - WEBSOCKET_ENABLED=true
      - SIGNUPS_ALLOWED=true
      - ADMIN_TOKEN=${VW_TOKEN}

volumes:
  nextcloud_db:
  nextcloud_redis:
  nextcloud_data:
  vaultwarden_data:
EOFC
}

generate_network_compose() {
  local server_url="${DUCKDNS_SUBDOMAIN:-homelab}.duckdns.org"
  [[ -z "$DUCKDNS_SUBDOMAIN" ]] && server_url="$HOST_IP"

  cat > "$HOMELAB_DIR/network/docker-compose.yml" << EOF
# Stack de red — Pi-hole + WireGuard + Grafana + Prometheus
services:

  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: always
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8053:80/tcp"
    volumes:
      - pihole_data:/etc/pihole
      - pihole_dnsmasq:/etc/dnsmasq.d
    environment:
      - TZ=${HOST_TZ}
      - WEBPASSWORD=${PIHOLE_PASS}
      - PIHOLE_DNS_=1.1.1.1;8.8.8.8
      - DNSMASQ_LISTENING=all
    cap_add:
      - NET_ADMIN

  wireguard:
    image: linuxserver/wireguard:latest
    container_name: wireguard
    restart: always
    ports:
      - "51820:51820/udp"
    volumes:
      - wireguard_data:/config
      - /lib/modules:/lib/modules:ro
    environment:
      - TZ=${HOST_TZ}
      - PUID=1000
      - PGID=1000
      - SERVERURL=${server_url}
      - SERVERPORT=51820
      - PEERS=${WG_PEERS}
      - PEERDNS=${HOST_IP}
      - INTERNAL_SUBNET=10.13.13.0
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: always
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)(\$\$|/)'

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: always
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - TZ=${HOST_TZ}
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASS}
      - GF_USERS_ALLOW_SIGN_UP=false

volumes:
  pihole_data:
  pihole_dnsmasq:
  wireguard_data:
  prometheus_data:
  grafana_data:
EOF

  cat > "$HOMELAB_DIR/network/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
}

generate_duckdns_compose() {
  cat > "$HOMELAB_DIR/duckdns/docker-compose.yml" << EOF
# DuckDNS — actualización automática de IP dinámica
services:
  duckdns:
    image: linuxserver/duckdns:latest
    container_name: duckdns
    restart: always
    environment:
      - TZ=${HOST_TZ}
      - SUBDOMAINS=${DUCKDNS_SUBDOMAIN}
      - TOKEN=${DUCKDNS_TOKEN}
      - LOG_FILE=false
EOF
}

# ─── INSTALACIÓN: STACKS ──────────────────────────────────────────

install_stack() {
  local name="$1"
  local dir="$2"
  local step_num="$3"

  clear_screen
  print_header
  status_step "${step_num}/$(count_steps)" "Levantar stack: ${BOLD}${name}${RESET}"
  echo

  status_info "Generando docker-compose.yml..."
  case "$name" in
    "Base")    generate_base_compose ;;
    "Medios")  generate_media_compose ;;
    "Cloud")   generate_cloud_compose ;;
    "Red")     generate_network_compose ;;
    "DuckDNS") generate_duckdns_compose ;;
  esac
  status_ok "Ficheros de configuración generados en ${BOLD}${dir}${RESET}"

  run_cmd "Descargando imágenes Docker para ${name}" \
    docker compose -f "${dir}/docker-compose.yml" pull

  run_cmd "Levantando contenedores de ${name}" \
    docker compose -f "${dir}/docker-compose.yml" up -d

  # Esperar a que los contenedores arranquen
  echo
  echo -ne "  ${DIM}Esperando a que los servicios arranquen${RESET}"
  for i in $(seq 1 5); do
    sleep 1
    echo -ne "${CYAN}.${RESET}"
  done
  echo

  # Mostrar estado
  echo
  docker compose -f "${dir}/docker-compose.yml" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | \
    while IFS= read -r line; do
      if echo "$line" | grep -q "Up\|running"; then
        echo -e "  ${GREEN}▶${RESET}  ${line}"
      else
        echo -e "  ${DIM}▷${RESET}  ${line}"
      fi
    done

  ((STEPS_DONE++))
  echo
  pause 2 "Siguiente paso en"
}

# ─── RESUMEN FINAL ────────────────────────────────────────────────

show_summary() {
  clear_screen
  print_header

  echo -e "  ${GREEN}${BOLD}✓  ¡Instalación completada!${RESET}"
  echo
  separator

  local domain="${DUCKDNS_SUBDOMAIN:-}.duckdns.org"
  [[ -z "$DUCKDNS_SUBDOMAIN" ]] && domain="$HOST_IP"

  echo -e "  ${BOLD}Acceso a tus servicios:${RESET}"
  echo

  if [[ "$INSTALL_BASE" == "true" ]]; then
    echo -e "  ${CYAN}BASE${RESET}"
    echo -e "  ${DIM}·${RESET}  Portainer            ${GREEN}https://${HOST_IP}:9443${RESET}"
    echo -e "  ${DIM}·${RESET}  Nginx Proxy Manager  ${GREEN}http://${HOST_IP}:81${RESET}  ${DIM}admin@example.com / changeme${RESET}"
    echo
  fi

  if [[ "$INSTALL_MEDIA" == "true" ]]; then
    echo -e "  ${MAGENTA}MEDIOS${RESET}"
    echo -e "  ${DIM}·${RESET}  Jellyfin             ${GREEN}http://${HOST_IP}:8096${RESET}"
    echo -e "  ${DIM}·${RESET}  Navidrome            ${GREEN}http://${HOST_IP}:4533${RESET}"
    echo
  fi

  if [[ "$INSTALL_CLOUD" == "true" ]]; then
    echo -e "  ${BLUE}CLOUD${RESET}"
    echo -e "  ${DIM}·${RESET}  Nextcloud            ${GREEN}http://${HOST_IP}:8080${RESET}"
    echo -e "  ${DIM}·${RESET}  Vaultwarden          ${GREEN}http://${HOST_IP}:8888${RESET}"
    echo -e "  ${DIM}·${RESET}  Vaultwarden Admin    ${GREEN}http://${HOST_IP}:8888/admin${RESET}"
    echo
  fi

  if [[ "$INSTALL_NETWORK" == "true" ]]; then
    echo -e "  ${YELLOW}RED Y SEGURIDAD${RESET}"
    echo -e "  ${DIM}·${RESET}  Pi-hole              ${GREEN}http://${HOST_IP}:8053/admin${RESET}"
    echo -e "  ${DIM}·${RESET}  Grafana              ${GREEN}http://${HOST_IP}:3000${RESET}  ${DIM}admin / tu contraseña${RESET}"
    echo -e "  ${DIM}·${RESET}  WireGuard            ${DIM}VPN en puerto UDP 51820${RESET}"
    echo -e "  ${DIM}·${RESET}  Clientes WG          ${GREEN}${HOMELAB_DIR}/network/config/${RESET}  ${DIM}(QR codes por cliente)${RESET}"
    echo
  fi

  separator
  echo
  echo -e "  ${BOLD}Próximos pasos recomendados:${RESET}"
  echo
  echo -e "  ${GREEN}1${RESET}  Cambia las credenciales por defecto de Nginx Proxy Manager"
  echo -e "  ${GREEN}2${RESET}  Configura subdominios con SSL en NPM para cada servicio"
  [[ "$INSTALL_NETWORK" == "true" ]] && \
    echo -e "  ${GREEN}3${RESET}  Apunta el DNS de tu router a ${BOLD}${HOST_IP}${RESET} para activar Pi-hole"
  [[ "$INSTALL_NETWORK" == "true" ]] && \
    echo -e "  ${GREEN}4${RESET}  Importa el dashboard Grafana ID ${BOLD}1860${RESET} (Node Exporter Full)"
  [[ "$INSTALL_CLOUD" == "true" ]] && \
    echo -e "  ${GREEN}5${RESET}  Pon SIGNUPS_ALLOWED=false en Vaultwarden tras crear tu cuenta"
  echo
  separator
  echo
  echo -e "  ${DIM}Log completo:  ${LOG_FILE}${RESET}"
  echo -e "  ${DIM}Ficheros:      ${HOMELAB_DIR}/${RESET}"
  echo
  echo -e "  ${CYAN}${BOLD}¡Disfruta tu homelab!  🖥️${RESET}"
  echo
}

# ─── UTILIDADES ───────────────────────────────────────────────────

count_steps() {
  local n=2  # sistema + docker siempre
  [[ "$INSTALL_BASE" == "true" ]]    && ((n++))
  [[ "$INSTALL_MEDIA" == "true" ]]   && ((n++))
  [[ "$INSTALL_CLOUD" == "true" ]]   && ((n++))
  [[ "$INSTALL_NETWORK" == "true" ]] && ((n++))
  [[ "$INSTALL_DUCKDNS" == "true" ]] && ((n++))
  echo "$n"
}

check_root() {
  if [[ "$EUID" -eq 0 ]]; then
    echo -e "${RED}No ejecutes este script como root.${RESET}"
    echo -e "Usa tu usuario normal; el script pedirá sudo cuando lo necesite."
    exit 1
  fi
}

check_sudo() {
  if ! sudo -v 2>/dev/null; then
    echo -e "${RED}Este usuario no tiene permisos sudo.${RESET}"
    exit 1
  fi
  # Mantener sudo activo durante la instalación
  while true; do sudo -n true; sleep 50; done &
  SUDO_KEEPALIVE_PID=$!
  trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null" EXIT
}

# ─── MAIN ─────────────────────────────────────────────────────────

main() {
  # Inicializar log
  echo "=== Homelab Install — $(date) ===" > "$LOG_FILE"

  check_root
  check_sudo

  # 1. Pantalla de bienvenida
  welcome_screen

  # 2. Selección de stacks
  menu_stacks

  # 3. Configuración
  wizard_config

  local step=1

  # 4. Sistema
  install_system
  ((step++))

  # 5. Docker
  install_docker
  ((step++))

  # 6. Stack base (siempre)
  install_stack "Base" "$HOMELAB_DIR/base" "$step"
  ((step++))

  # 7. Stacks opcionales
  if [[ "$INSTALL_DUCKDNS" == "true" ]]; then
    install_stack "DuckDNS" "$HOMELAB_DIR/duckdns" "$step"
    ((step++))
  fi

  if [[ "$INSTALL_NETWORK" == "true" ]]; then
    install_stack "Red" "$HOMELAB_DIR/network" "$step"
    ((step++))
  fi

  if [[ "$INSTALL_MEDIA" == "true" ]]; then
    install_stack "Medios" "$HOMELAB_DIR/media" "$step"
    ((step++))
  fi

  if [[ "$INSTALL_CLOUD" == "true" ]]; then
    install_stack "Cloud" "$HOMELAB_DIR/cloud" "$step"
    ((step++))
  fi

  # 8. Resumen
  show_summary
}

main "$@"
