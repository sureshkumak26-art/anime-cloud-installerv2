#!/usr/bin/env bash
set -Eeuo pipefail
R='\033[0m'; C='\033[96m'; G='\033[92m'; Y='\033[93m'; M='\033[95m'; RED='\033[91m'; B='\033[1m'
BASE=/opt/anime-cloud; PANEL=/var/www/pterodactyl; WINGS=/etc/pterodactyl; LOG=$BASE/install.log
mkdir -p "$BASE"; touch "$LOG"; exec > >(tee -a "$LOG") 2>&1
trap 'echo -e "${RED}✘ Error on line $LINENO${R}"' ERR
ok(){ echo -e "${G}✔${R} $*"; }; warn(){ echo -e "${Y}⚠${R} $*"; }; die(){ echo -e "${RED}✘${R} $*"; exit 1; }; pause(){ read -rp 'Press ENTER to continue...'; }
banner(){ clear; echo -e "${C}${B}╔════════════════════════════════════════════════════════╗${R}"; echo -e "${C}${B}║             ✦  A N I M E   C L O U D  ✦               ║${R}"; echo -e "${C}${B}║                 3D NEON EDITION V3                    ║${R}"; echo -e "${C}${B}╚════════════════════════════════════════════════════════╝${R}"; echo -e "${M}${B}        █████╗ ███╗   ██╗██╗███╗   ███╗███████╗${R}"; echo -e "${C}${B}       ██╔══██╗████╗  ██║██║████╗ ████║██╔════╝${R}"; echo -e "${G}${B}       ███████║██╔██╗ ██║██║██╔████╔██║█████╗  ${R}"; echo -e "${Y}${B}       ██╔══██║██║╚██╗██║██║██║╚██╔╝██║██╔══╝  ${R}"; echo -e "${C}${B}       ██║  ██║██║ ╚████║██║██║ ╚═╝ ██║███████╗${R}"; echo -e "${M}${B}       ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚══════╝${R}"; echo; echo -e "${M}${B}│           ✦ Created by the mrhacker ✦                 │${R}"; printf "${C}${B}  3D interface ${R}"; for _ in 1 2 3 4 5 6; do printf "${M}◆${R}"; sleep 0.04; done; echo -e " ${G}${B} ONLINE${R}"; echo; }
root(){ [[ $EUID -eq 0 ]] || die 'Run as root.'; }
os(){ source /etc/os-release; [[ $ID == ubuntu || $ID == debian ]] || die 'Ubuntu/Debian required.'; ok "OS: $PRETTY_NAME"; }
neon_progress(){ echo -ne "${C}${B}${1:-Starting}${R} "; for _ in 1 2 3 4 5 6 7 8; do printf "${M}◆${R}"; sleep 0.04; done; echo -e " ${G}${B}OK${R}"; }
system_detect(){ banner; echo -e "${C}${B}╭────────────── 🔍 AUTO SERVER DETECTION ──────────────╮${R}"; source /etc/os-release; echo -e "${G}OS:${R} $PRETTY_NAME"; echo -e "${G}Kernel:${R} $(uname -r)"; echo -e "${G}Architecture:${R} $(uname -m)"; echo -e "${G}CPU:${R} $(nproc) cores / $(lscpu 2>/dev/null|awk -F: '/Model name/{gsub(/^ +/,"",$2); print $2; exit}')"; echo -e "${G}RAM:${R} $(free -h|awk '/Mem:/{print $3" / "$2}')"; echo -e "${G}Swap:${R} $(free -h|awk '/Swap:/{print $3" / "$2}')"; echo -e "${G}Disk:${R} $(df -h /|awk 'NR==2{print $3" / "$2" ("$5")"}')"; echo -e "${G}Public IPv4:${R} $(curl -4 -fsS --max-time 5 https://api.ipify.org || echo unknown)"; echo -e "${G}Private IPv4:${R} $(hostname -I|awk '{print $1}')"; echo -e "${G}Virtualization:${R} $(systemd-detect-virt 2>/dev/null || echo unknown)"; echo -e "${G}Docker:${R} $(command -v docker >/dev/null && docker --version || echo not-installed)"; echo -e "${G}PHP:${R} $(php -v 2>/dev/null|head -1 || echo not-installed)"; echo; for s in mariadb redis-server nginx docker pteroq wings cloudflared; do systemctl is-active --quiet "$s" 2>/dev/null && echo -e "${G}● RUNNING${R} $s" || echo -e "${RED}● STOPPED${R} $s"; done; echo; echo -e "${Y}Open TCP ports:${R}"; ss -lnt 2>/dev/null|awk 'NR>1{print $4}'|sed 's/.*://'|sort -n|uniq|tr '\n' ' '; echo; echo -e "${C}${B}╰────────────────────────────────────────────────────────╯${R}"; pause; }
info(){ system_detect; }
deps(){ apt-get update -y; apt-get install -y curl wget git unzip tar gzip ca-certificates gnupg lsb-release software-properties-common apt-transport-https jq mariadb-server redis-server nginx certbot python3-certbot-nginx ufw cron openssl; systemctl enable --now mariadb redis-server nginx; ok 'Dependencies installed.'; }
php(){ source /etc/os-release; if [[ $ID == ubuntu ]]; then add-apt-repository -y ppa:ondrej/php || true; else echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list; curl -fsSL https://packages.sury.org/php/apt.gpg|gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/php.gpg; fi; apt-get update -y; apt-get install -y php8.3 php8.3-cli php8.3-fpm php8.3-common php8.3-mysql php8.3-gd php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-opcache; systemctl enable --now php8.3-fpm; ok 'PHP 8.3 installed.'; }
composer(){ command -v composer >/dev/null || { curl -fsSL https://getcomposer.org/installer -o /tmp/c.php; php /tmp/c.php --install-dir=/usr/local/bin --filename=composer; rm -f /tmp/c.php; }; composer --version; }
database(){ DBPASS=$(openssl rand -hex 24); mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
printf 'DB_DATABASE=panel\nDB_USERNAME=pterodactyl\nDB_PASSWORD=%s\nDB_HOST=127.0.0.1\nDB_PORT=3306\n' "$DBPASS" > "$BASE/database.env"; chmod 600 "$BASE/database.env"; ok 'Database created.'; }
panel(){ mkdir -p "$PANEL"; cd "$PANEL"; curl -fL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz -o panel.tar.gz; tar -xzf panel.tar.gz; rm -f panel.tar.gz; cp -n .env.example .env || true; composer install --no-dev --optimize-autoloader --no-interaction; php artisan key:generate --force; chown -R www-data:www-data "$PANEL"; chmod -R 755 storage bootstrap/cache; ok 'Pterodactyl Panel installed.'; }
panelcfg(){ read -rp 'Panel domain: ' DOMAIN; [[ -n "$DOMAIN" ]] || die 'Domain required.'; read -rp 'Admin email: ' EMAIL; [[ -n "$EMAIL" ]] || die 'Email required.'; source "$BASE/database.env"; cd "$PANEL"; php artisan p:environment:setup --author="$EMAIL" --url="https://$DOMAIN" --timezone="Asia/Kolkata" --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-port=6379; php artisan p:environment:database --host="$DB_HOST" --port="$DB_PORT" --database="$DB_DATABASE" --username="$DB_USERNAME" --password="$DB_PASSWORD"; php artisan migrate --seed --force; chown -R www-data:www-data "$PANEL"; printf 'DOMAIN=%s\nEMAIL=%s\n' "$DOMAIN" "$EMAIL" > "$BASE/panel.env"; chmod 600 "$BASE/panel.env"; ok 'Panel configured.'; }
nginx(){ source "$BASE/panel.env"; cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server { listen 80; listen [::]:80; server_name $DOMAIN; root $PANEL/public; index index.php; client_max_body_size 100M; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include fastcgi_params; fastcgi_pass unix:/run/php/php8.3-fpm.sock; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; } location ~ /\.ht { deny all; } }
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf; rm -f /etc/nginx/sites-enabled/default; nginx -t; systemctl restart nginx; ok 'Nginx configured.'; }
queue(){ cat >/etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $PANEL/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable --now pteroq; ok 'Queue worker enabled.'; }
docker(){ command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh; systemctl enable --now docker; docker --version; }
wings(){ mkdir -p "$WINGS"; case "$(uname -m)" in x86_64) BIN=wings_linux_amd64;; aarch64|arm64) BIN=wings_linux_arm64;; *) die 'Unsupported architecture.';; esac; curl -fL "https://github.com/pterodactyl/wings/releases/latest/download/$BIN" -o /usr/local/bin/wings; chmod +x /usr/local/bin/wings; cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=$WINGS
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable wings; [[ -f $WINGS/config.yml ]] && systemctl restart wings || warn 'Wings installed; add Node config to /etc/pterodactyl/config.yml.'; }
tunnel(){ banner; echo 'Create a Cloudflare Tunnel and paste its token.'; read -rsp 'Tunnel token: ' TOKEN; echo; [[ -n "$TOKEN" ]] || die 'Token required.'; case "$(uname -m)" in x86_64) PKG=cloudflared-linux-amd64.deb;; aarch64|arm64) PKG=cloudflared-linux-arm64.deb;; *) die 'Unsupported architecture.';; esac; curl -fL "https://github.com/cloudflare/cloudflared/releases/latest/download/$PKG" -o /tmp/cf.deb; apt-get install -y /tmp/cf.deb; rm -f /tmp/cf.deb; cloudflared service uninstall >/dev/null 2>&1 || true; cloudflared service install "$TOKEN"; systemctl enable --now cloudflared; ok 'Cloudflare Tunnel running.'; }
ssl(){ source "$BASE/panel.env"; read -rp "SSL email [$EMAIL]: " E; E=${E:-$EMAIL}; certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$E" --redirect; }
firewall(){ apt-get install -y ufw; ufw default deny incoming; ufw default allow outgoing; ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 2022/tcp; ufw --force enable; ok 'Firewall enabled.'; }
health(){ banner; for s in mariadb redis-server php8.3-fpm nginx docker pteroq wings cloudflared; do systemctl is-active --quiet "$s" 2>/dev/null && echo -e "${G}✔ $s${R}" || echo -e "${RED}✘ $s${R}"; done; echo "Wings config: $([[ -f $WINGS/config.yml ]] && echo FOUND || echo MISSING)"; echo "Log: $LOG"; pause; }
admin(){ cd "$PANEL"; php artisan p:user:make; }
full(){ banner; system_detect; read -rp 'Start FULL AUTO INSTALL? [y/N]: ' A; [[ "$A" =~ ^[Yy]$ ]] || return; neon_progress 'Initializing Anime Cloud 3D'; deps; php; composer; database; panel; panelcfg; nginx; queue; docker; wings; tunnel; ssl; firewall; admin; health; banner; echo -e "${G}${B}✔ INSTALLATION COMPLETE${R}"; pause; }
container_tools(){ while true; do banner; echo -e "${C}${B}╭────────────── 📦 CONTAINER TOOLS ─────────────────────╮${R}"; echo -e "│ ${G}[1]${R} 🖥️ INSTALL LINUX RDP (XRDP)"; echo -e "│ ${G}[2]${R} 🐳 RDP GUI DOCKER CONTAINER"; echo -e "│ ${G}[3]${R} 🔍 RDP STATUS"; echo -e "│ ${G}[4]${R} 🛑 STOP RDP"; echo -e "│ ${G}[5]${R} 🗑️ REMOVE RDP"; echo -e "│ ${RED}[0]${R} ↩ BACK"; echo; read -rp 'Container Tools > ' r; case "$r" in 1) apt-get update -y; apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11; systemctl enable --now xrdp; ufw allow 3389/tcp 2>/dev/null || true; ok 'Linux RDP installed on port 3389.'; pause;; 2) command -v docker >/dev/null || { warn 'Docker required.'; pause; continue; }; read -rp 'Container name [anime-rdp]: ' NAME; NAME=${NAME:-anime-rdp}; read -rp 'Host port [3389]: ' PORT; PORT=${PORT:-3389}; docker rm -f "$NAME" >/dev/null 2>&1 || true; docker run -d --name "$NAME" --restart unless-stopped -p "${PORT}:3389" dorowu/ubuntu-desktop-lxde-vnc:latest; ufw allow "${PORT}/tcp" 2>/dev/null || true; ok "RDP container started: $NAME:$PORT"; pause;; 3) systemctl is-active --quiet xrdp && ok 'xrdp RUNNING' || warn 'xrdp STOPPED'; docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}'; pause;; 4) systemctl disable --now xrdp 2>/dev/null || true; docker ps --format '{{.Names}}'|grep -E 'anime-rdp|rdp'|xargs -r docker stop; warn 'RDP stopped.'; pause;; 5) systemctl disable --now xrdp 2>/dev/null || true; apt-get purge -y xrdp 2>/dev/null || true; docker ps -a --format '{{.Names}}'|grep -E 'anime-rdp|rdp'|xargs -r docker rm -f; warn 'RDP removed.'; pause;; 0) return;; *) warn 'Invalid option.';; esac; done; }
menu(){ while true; do banner; echo -e "${C}${B}╭──────────── 🚀 DEPLOYMENT & SERVICES ────────────────╮${R}"; echo -e "│ ${G}[1]${R} 🚀 FULL AUTO INSTALL"; echo -e "│ ${G}[2]${R} 🖥️ AUTO SYSTEM DETECT"; echo -e "│ ${G}[3]${R} ⚙️ WINGS AUTO SETUP"; echo -e "│ ${G}[4]${R} 🦎 PTERODACTYL PANEL"; echo -e "│ ${G}[5]${R} 🐳 DOCKER"; echo -e "│ ${G}[6]${R} 📊 SERVICE MONITOR"; echo -e "│ ${G}[7]${R} 📦 CONTAINER TOOLS / RDP"; echo -e "${C}${B}╰────────────────────────────────────────────────────────╯${R}"; echo; echo -e "${M}${B}╭────────────── ☁ CLOUD & SECURITY ────────────────────╮${R}"; echo -e "│ ${M}[8]${R} ☁️ CLOUDFLARE TUNNEL"; echo -e "│ ${M}[9]${R} 🌐 CLOUDFLARE DNS"; echo -e "│ ${M}[10]${R} 🔒 LET'S ENCRYPT SSL"; echo -e "│ ${M}[11]${R} 🛡️ FIREWALL"; echo -e "│ ${M}[12]${R} 🔍 HEALTH CHECK"; echo -e "${M}${B}╰────────────────────────────────────────────────────────╯${R}"; echo; echo -e "${Y}${B}╭──────────────── ✨ TOOLS ─────────────────────────────╮${R}"; echo -e "│ ${Y}[13]${R} ✨ AUTO REPAIR / REINSTALL"; echo -e "│ ${Y}[14]${R} 📝 INSTALL LOG"; echo -e "│ ${RED}[0]${R} ⏻ EXIT"; echo -e "${Y}${B}╰────────────────────────────────────────────────────────╯${R}"; echo; echo -ne "${C}${B}╭─[ Anime Cloud 3D ]─➜ ${R}"; read -r O; case "$O" in 1) full;; 2) system_detect;; 3) wings; pause;; 4) panel; panelcfg; nginx; queue; pause;; 5) docker; pause;; 6) info;; 7) container_tools;; 8) tunnel; pause;; 9) warn 'Configure Cloudflare DNS/API separately.'; pause;; 10) ssl; pause;; 11) firewall; pause;; 12) health;; 13) full;; 14) clear; less "$LOG";; 0) clear; exit 0;; *) warn 'Invalid option.'; sleep 1;; esac; done; }
root; os; menu
