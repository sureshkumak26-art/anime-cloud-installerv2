#!/usr/bin/env bash

# ==============================================================
#                    ANIME CLOUD INSTALLER
# ==============================================================
# Pterodactyl Panel + Wings + Docker + Cloudflare + SSL
# Ubuntu 22.04 / 24.04
# Debian 11 / 12 / 13
#
# Run:
#   chmod +x anime-cloud.sh
#   sudo ./anime-cloud.sh
# ==============================================================

set -Eeuo pipefail

# ==============================================================
# COLORS
# ==============================================================

RESET="\033[0m"

BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

BRIGHT_BLACK="\033[90m"
BRIGHT_RED="\033[91m"
BRIGHT_GREEN="\033[92m"
BRIGHT_YELLOW="\033[93m"
BRIGHT_BLUE="\033[94m"
BRIGHT_MAGENTA="\033[95m"
BRIGHT_CYAN="\033[96m"
BRIGHT_WHITE="\033[97m"

BOLD="\033[1m"
DIM="\033[2m"

# ==============================================================
# VARIABLES
# ==============================================================

PANEL_DIR="/var/www/pterodactyl"
WINGS_DIR="/etc/pterodactyl"
WINGS_BIN="/usr/local/bin/wings"

ANIME_DIR="/root/anime-cloud"
LOG_FILE="$ANIME_DIR/install.log"

CF_API="https://api.cloudflare.com/client/v4"

mkdir -p "$ANIME_DIR"
chmod 700 "$ANIME_DIR"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# ==============================================================
# LOGGING
# ==============================================================

exec > >(tee -a "$LOG_FILE") 2>&1

# ==============================================================
# ERROR HANDLER
# ==============================================================

error_handler() {

    local line="$1"

    echo
    echo -e "${BRIGHT_RED}${BOLD}✘ INSTALLER ERROR${RESET}"
    echo -e "${WHITE}Line:${RESET} $line"
    echo -e "${WHITE}Log:${RESET} $LOG_FILE"
    echo

}

trap 'error_handler $LINENO' ERR

# ==============================================================
# BASIC FUNCTIONS
# ==============================================================

pause_screen() {

    echo
    read -rp "  Press ENTER to continue..."
}

loading() {

    local msg="$1"

    echo -ne "${BRIGHT_CYAN}${msg}${RESET}"

    for _ in 1 2 3; do
        echo -ne "${BRIGHT_MAGENTA}.${RESET}"
        sleep 0.25
    done

    echo
}

success() {

    echo -e "${BRIGHT_GREEN}${BOLD}✔${RESET} ${WHITE}$1${RESET}"

}

warning() {

    echo -e "${BRIGHT_YELLOW}${BOLD}⚠${RESET} ${WHITE}$1${RESET}"

}

failure() {

    echo -e "${BRIGHT_RED}${BOLD}✘${RESET} ${WHITE}$1${RESET}"

}

info() {

    echo -e "${BRIGHT_CYAN}${BOLD}➜${RESET} ${WHITE}$1${RESET}"

}

# ==============================================================
# BANNER
# ==============================================================

anime_banner() {

    clear

    echo
    echo -e "${BRIGHT_MAGENTA}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║       █████╗ ███╗   ██╗██╗███╗   ███╗███████╗          ║"
    echo "║      ██╔══██╗████╗  ██║██║████╗ ████║██╔════╝          ║"
    echo "║      ███████║██╔██╗ ██║██║██╔████╔██║█████╗            ║"
    echo "║      ██╔══██║██║╚██╗██║██║██║╚██╔╝██║██╔══╝            ║"
    echo "║      ██║  ██║██║ ╚████║██║██║ ╚═╝ ██║███████╗          ║"
    echo "║      ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚══════╝          ║"
    echo "║                                                          ║"
    echo -e "║       ${BRIGHT_CYAN}☁  CLOUD HOSTING CONTROL CENTER  ☁${BRIGHT_MAGENTA}       ║"
    echo -e "║       ${BRIGHT_YELLOW}PTERODACTYL • WINGS • CLOUDFLARE${BRIGHT_MAGENTA}          ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"

    echo -e "${BRIGHT_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    echo -e " ${BRIGHT_GREEN}●${RESET} ${WHITE}Anime Cloud Installer${RESET} ${BRIGHT_BLACK}v3.0${RESET}"
    echo -e " ${BRIGHT_GREEN}●${RESET} ${WHITE}Server:${RESET} ${BRIGHT_CYAN}$(hostname)${RESET}"

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo -e " ${BRIGHT_GREEN}●${RESET} ${WHITE}OS:${RESET} ${BRIGHT_CYAN}${PRETTY_NAME}${RESET}"
    fi

    echo -e "${BRIGHT_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo

}

# ==============================================================
# ROOT CHECK
# ==============================================================

check_root() {

    if [[ "$EUID" -ne 0 ]]; then

        failure "Run this script as root."

        echo
        echo "Example:"
        echo "sudo ./anime-cloud.sh"

        exit 1

    fi

}

# ==============================================================
# OS CHECK
# ==============================================================

check_os() {

    if [[ ! -f /etc/os-release ]]; then

        failure "Cannot detect operating system."
        exit 1

    fi

    . /etc/os-release

    case "$ID" in

        ubuntu|debian)
            ;;

        *)
            failure "Unsupported OS: $ID"
            echo
            echo "Supported:"
            echo "Ubuntu 22.04 / 24.04"
            echo "Debian 11 / 12 / 13"
            exit 1
            ;;

    esac

    success "Operating system detected: $PRETTY_NAME"

}

# ==============================================================
# ARCHITECTURE
# ==============================================================

check_architecture() {

    ARCH="$(uname -m)"

    case "$ARCH" in

        x86_64)
            WINGS_ARCH="amd64"
            ;;

        aarch64|arm64)
            WINGS_ARCH="arm64"
            ;;

        *)
            failure "Unsupported CPU architecture: $ARCH"
            exit 1
            ;;

    esac

    success "Architecture: $ARCH"

}

# ==============================================================
# SYSTEM DEPENDENCIES
# ==============================================================

install_base() {

    anime_banner

    info "Updating package lists..."

    apt-get update -y

    info "Installing system dependencies..."

    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        tar \
        gzip \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        jq \
        dnsutils \
        sudo \
        nano \
        vim \
        ufw \
        cron \
        logrotate \
        openssl \
        iproute2 \
        procps \
        htop

    success "System dependencies installed."

    pause_screen

}

# ==============================================================
# PHP
# ==============================================================

install_php() {

    anime_banner

    . /etc/os-release

    info "Installing PHP 8.3..."

    if [[ "$ID" == "ubuntu" ]]; then

        apt-get install -y software-properties-common

        if ! grep -Rqs "ondrej/php" /etc/apt/sources.list.d/ 2>/dev/null; then
            add-apt-repository -y ppa:ondrej/php
        fi

    elif [[ "$ID" == "debian" ]]; then

        apt-get install -y \
            lsb-release \
            ca-certificates \
            apt-transport-https

        if [[ ! -f /etc/apt/sources.list.d/php.list ]]; then

            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/php.list

            curl -fsSL https://packages.sury.org/php/apt.gpg \
                | gpg --dearmor \
                -o /etc/apt/trusted.gpg.d/php.gpg

        fi

    fi

    apt-get update -y

    apt-get install -y \
        php8.3 \
        php8.3-cli \
        php8.3-common \
        php8.3-gd \
        php8.3-mysql \
        php8.3-mbstring \
        php8.3-bcmath \
        php8.3-xml \
        php8.3-fpm \
        php8.3-curl \
        php8.3-zip \
        php8.3-opcache

    systemctl enable --now php8.3-fpm

    success "PHP 8.3 installed."

    php -v | head -n 1

    pause_screen

}

# ==============================================================
# PHP CONFIG
# ==============================================================

configure_php() {

    anime_banner

    local ini="/etc/php/8.3/fpm/php.ini"

    if [[ -f "$ini" ]]; then

        sed -i \
            's/^;*upload_max_filesize.*/upload_max_filesize = 100M/' \
            "$ini"

        sed -i \
            's/^;*post_max_size.*/post_max_size = 100M/' \
            "$ini"

        sed -i \
            's/^;*memory_limit.*/memory_limit = 512M/' \
            "$ini"

    fi

    systemctl restart php8.3-fpm

    success "PHP configured."

    pause_screen

}

# ==============================================================
# DATABASE + REDIS
# ==============================================================

install_database() {

    anime_banner

    info "Installing MariaDB..."

    apt-get install -y \
        mariadb-server \
        mariadb-client

    systemctl enable --now mariadb

    info "Installing Redis..."

    apt-get install -y redis-server

    systemctl enable --now redis-server

    success "MariaDB and Redis installed."

    pause_screen

}

# ==============================================================
# DATABASE CREATION
# ==============================================================

create_database() {

    anime_banner

    local db_name="panel"
    local db_user="pterodactyl"
    local db_password

    db_password="$(openssl rand -hex 24)"

    info "Creating Pterodactyl database..."

    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
CREATE USER IF NOT EXISTS '${db_user}'@'127.0.0.1'
IDENTIFIED BY '${db_password}';
ALTER USER '${db_user}'@'127.0.0.1'
IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES
ON \`${db_name}\`.*
TO '${db_user}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

    cat > "$ANIME_DIR/database.txt" <<EOF
DATABASE_NAME=${db_name}
DATABASE_USER=${db_user}
DATABASE_PASSWORD=${db_password}
DATABASE_HOST=127.0.0.1
DATABASE_PORT=3306
EOF

    chmod 600 "$ANIME_DIR/database.txt"

    success "Database created."

    echo
    echo -e "${BRIGHT_YELLOW}Database credentials:${RESET}"
    echo "$ANIME_DIR/database.txt"

    pause_screen

}

# ==============================================================
# COMPOSER
# ==============================================================

install_composer() {

    anime_banner

    if command -v composer >/dev/null 2>&1; then

        success "Composer already installed."

        composer --version

        pause_screen
        return

    fi

    info "Installing Composer..."

    apt-get install -y php-cli curl unzip

    EXPECTED="$(curl -fsSL https://composer.github.io/installer.sig)"

    php -r \
        "copy('https://getcomposer.org/installer', 'composer-setup.php');"

    ACTUAL="$(php -r \
        "echo hash_file('sha384', 'composer-setup.php');")"

    if [[ "$EXPECTED" != "$ACTUAL" ]]; then

        rm -f composer-setup.php

        failure "Composer checksum verification failed."

        exit 1

    fi

    php composer-setup.php \
        --install-dir=/usr/local/bin \
        --filename=composer

    rm -f composer-setup.php

    success "Composer installed."

    composer --version

    pause_screen

}

# ==============================================================
# PTERODACTYL PANEL DOWNLOAD
# ==============================================================

download_panel() {

    anime_banner

    mkdir -p "$PANEL_DIR"

    cd "$PANEL_DIR"

    info "Downloading latest Pterodactyl Panel..."

    rm -f panel.tar.gz

    curl -fL \
        -o panel.tar.gz \
        https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz

    tar -xzf panel.tar.gz

    rm -f panel.tar.gz

    if [[ ! -f .env ]]; then
        cp .env.example .env
    fi

    chown -R www-data:www-data "$PANEL_DIR"

    chmod -R 755 \
        "$PANEL_DIR/storage" \
        "$PANEL_DIR/bootstrap/cache"

    success "Pterodactyl Panel downloaded."

    pause_screen

}

# ==============================================================
# PANEL DEPENDENCIES
# ==============================================================

install_panel_dependencies() {

    anime_banner

    cd "$PANEL_DIR"

    info "Installing Panel dependencies..."

    COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev \
        --optimize-autoloader \
        --no-interaction

    php artisan key:generate --force

    chown -R www-data:www-data "$PANEL_DIR"

    success "Panel dependencies installed."

    pause_screen

}

# ==============================================================
# PANEL CONFIG
# ==============================================================

configure_panel() {

    anime_banner

    if [[ ! -f "$PANEL_DIR/artisan" ]]; then

        failure "Pterodactyl Panel is not installed."

        pause_screen
        return

    fi

    if [[ ! -f "$ANIME_DIR/database.txt" ]]; then

        failure "Database credentials are missing."

        echo "Run Database + Redis first."

        pause_screen
        return

    fi

    . "$ANIME_DIR/database.txt"

    read -rp \
        "  Panel domain (example: panel.example.com): " \
        PANEL_DOMAIN

    if [[ -z "$PANEL_DOMAIN" ]]; then

        failure "Domain cannot be empty."

        pause_screen
        return

    fi

    read -rp \
        "  Admin email: " \
        ADMIN_EMAIL

    if [[ -z "$ADMIN_EMAIL" ]]; then

        failure "Email cannot be empty."

        pause_screen
        return

    fi

    read -rp \
        "  Timezone [Asia/Kolkata]: " \
        PANEL_TIMEZONE

    PANEL_TIMEZONE="${PANEL_TIMEZONE:-Asia/Kolkata}"

    cat > "$ANIME_DIR/panel.conf" <<EOF
PANEL_DOMAIN=${PANEL_DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
PANEL_TIMEZONE=${PANEL_TIMEZONE}
EOF

    chmod 600 "$ANIME_DIR/panel.conf"

    cd "$PANEL_DIR"

    info "Configuring application..."

    php artisan p:environment:setup \
        --author="$ADMIN_EMAIL" \
        --url="https://$PANEL_DOMAIN" \
        --timezone="$PANEL_TIMEZONE" \
        --cache=redis \
        --session=redis \
        --queue=redis \
        --redis-host=127.0.0.1 \
        --redis-port=6379

    info "Configuring database..."

    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="$DATABASE_NAME" \
        --username="$DATABASE_USER" \
        --password="$DATABASE_PASSWORD"

    info "Running migrations..."

    php artisan migrate --seed --force

    chown -R www-data:www-data "$PANEL_DIR"

    success "Panel configured."

    pause_screen

}

# ==============================================================
# ADMIN USER
# ==============================================================

create_admin() {

    anime_banner

    if [[ ! -f "$PANEL_DIR/artisan" ]]; then

        failure "Panel is not installed."

        pause_screen
        return

    fi

    cd "$PANEL_DIR"

    php artisan p:user:make

    success "Admin setup completed."

    pause_screen

}

# ==============================================================
# NGINX
# ==============================================================

configure_nginx() {

    anime_banner

    apt-get install -y nginx

    if [[ -f "$ANIME_DIR/panel.conf" ]]; then
        . "$ANIME_DIR/panel.conf"
    else

        read -rp \
            "  Panel domain: " \
            PANEL_DOMAIN

    fi

    if [[ -z "${PANEL_DOMAIN:-}" ]]; then

        failure "Panel domain missing."

        pause_screen
        return

    fi

    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {

    listen 80;
    listen [::]:80;

    server_name ${PANEL_DOMAIN};

    root ${PANEL_DIR}/public;

    index index.php;

    client_max_body_size 100M;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    location / {

        try_files \$uri \$uri/ /index.php?\$query_string;

    }

    location ~ \.php$ {

        fastcgi_split_path_info ^(.+\.php)(/.+)\$;

        fastcgi_pass unix:/run/php/php8.3-fpm.sock;

        fastcgi_index index.php;

        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;

    }

    location ~ /\.ht {

        deny all;

    }

}
EOF

    ln -sf \
        /etc/nginx/sites-available/pterodactyl.conf \
        /etc/nginx/sites-enabled/pterodactyl.conf

    rm -f /etc/nginx/sites-enabled/default

    nginx -t

    systemctl enable --now nginx
    systemctl restart nginx

    chown -R www-data:www-data "$PANEL_DIR"

    success "Nginx configured."

    pause_screen

}

# ==============================================================
# QUEUE
# ==============================================================

configure_queue() {

    anime_banner

    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
Requires=redis-server.service

[Service]
User=www-data
Group=www-data

Restart=always
RestartSec=5

ExecStart=/usr/bin/php \
/var/www/pterodactyl/artisan \
queue:work \
--queue=high,standard,low \
--sleep=3 \
--tries=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq

    success "Queue worker configured."

    pause_screen

}

# ==============================================================
# DOCKER
# ==============================================================

install_docker() {

    anime_banner

    if command -v docker >/dev/null 2>&1; then

        success "Docker already installed."

    else

        info "Installing Docker..."

        curl -fsSL https://get.docker.com | sh

    fi

    systemctl enable --now docker

    docker --version

    success "Docker ready."

    pause_screen

}

# ==============================================================
# WINGS
# ==============================================================

install_wings() {

    anime_banner

    check_architecture

    mkdir -p "$WINGS_DIR"

    info "Downloading Pterodactyl Wings..."

    curl -fL \
        -o "$WINGS_BIN" \
        "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"

    chmod 755 "$WINGS_BIN"

    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl

LimitNOFILE=4096

ExecStart=/usr/local/bin/wings

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings

    success "Wings installed."

    echo
    echo -e "${BRIGHT_YELLOW}${BOLD}WINGS CONFIGURATION REQUIRED${RESET}"
    echo
    echo "Create a Node in:"
    echo "Pterodactyl → Admin → Nodes"
    echo
    echo "Copy the generated configuration to:"
    echo
    echo "$WINGS_DIR/config.yml"
    echo
    echo "Then run:"
    echo
    echo "systemctl restart wings"

    pause_screen

}

# ==============================================================
# CLOUDFLARE DNS
# ==============================================================

configure_cloudflare() {

    anime_banner

    echo -e "${BRIGHT_YELLOW}${BOLD}Cloudflare API Token${RESET}"
    echo
    echo "Required permissions:"
    echo "  Zone → Zone → Read"
    echo "  Zone → DNS → Edit"
    echo

    read -rsp \
        "  Cloudflare API Token: " \
        CF_TOKEN

    echo

    if [[ -z "$CF_TOKEN" ]]; then

        failure "Token cannot be empty."

        pause_screen
        return

    fi

    read -rp \
        "  Cloudflare domain (example.com): " \
        CF_DOMAIN

    CF_DOMAIN="${CF_DOMAIN#https://}"
    CF_DOMAIN="${CF_DOMAIN#http://}"
    CF_DOMAIN="${CF_DOMAIN%%/*}"

    if [[ -z "$CF_DOMAIN" ]]; then

        failure "Domain cannot be 