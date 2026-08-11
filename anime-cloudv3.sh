#!/usr/bin/env bash
# Anime Cloud Installer V3
# Pterodactyl Panel + Wings + Docker + Cloudflare Tunnel
# Ubuntu 22.04/24.04, Debian 11/12/13
set -Eeuo pipefail

R='\033[0m'; B='\033[1m'; C='\033[96m'; G='\033[92m'; Y='\033[93m'; M='\033[95m'; W='\033[97m'; RED='\033[91m'; BL='\033[94m'
BASE=/opt/anime-cloud; PANEL=/var/www/pterodactyl; WINGS=/etc/pterodactyl; LOG=$BASE/install.log
mkdir -p "$BASE"; touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

ok(){ echo -e "${G}${B}✔${R} $*"; }
err(){ echo -e "${RED}${B}✘${R} $*"; }
info(){ echo -e "${C}➜${R} $*"; }
warn(){ echo -e "${Y}⚠${R} $*"; }
pause(){ read -rp $'\nPress ENTER to continue...'; }

banner(){ clear; echo -e "${M}${B}╔════════════════════════════════════════════════════════════╗\n║                  ANIME CLOUD INSTALLER V3                 ║\n║             PTERODACTYL • WINGS • CLOUDFLARE              ║\n╚════════════════════════════════════════════════════════════╝${R}"; }

trap 'err "Installation stopped at line $LINENO. Log: $LOG"' ERR
[[ $EUID -eq 0 ]] || { err 'Run as root.'; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu || "$ID" == debian ]] || { err "Unsupported OS: $ID"; exit 1; }
ARCH=$(uname -m); case "$ARCH" in x86_64) WA=amd64;; aarch64|arm64) WA=arm64;; *) err "Unsupported architecture $ARCH"; exit 1;; esac

base(){ banner; apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git unzip tar gzip ca-certificates gnupg jq sudo nano nginx mariadb-server redis-server cron openssl ufw; systemctl enable --now mariadb redis-server nginx cron; ok 'Base packages ready'; pause; }

php(){ banner; apt-get install -y software-properties-common; if [[ "$ID" == ubuntu ]]; then add-apt-repository -y ppa:ondrej/php || true; else apt-get install -y lsb-release ca-certificates apt-transport-https; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list; curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg; fi; apt-get update -y; apt-get install -y php8.3 php8.3-cli php8.3-fpm php8.3-common php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-opcache; systemctl enable --now php8.3-fpm; ok 'PHP 8.3 ready'; pause; }

db(){ banner; local p; p=$(openssl rand -hex 24); mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$p';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$p';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
printf 'DB_NAME=panel\nDB_USER=pterodactyl\nDB_PASS=%s\nDB_HOST=127.0.0.1\nDB_PORT=3306\n' "$p" >$BASE/database.conf; chmod 600 $BASE/database.conf; ok 'Database created'; pause; }

composer(){ banner; if ! command -v composer >/dev/null; then php -r "copy('https://getcomposer.org/installer','/tmp/composer.php');"; php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer; rm -f /tmp/composer.php; fi; ok 'Composer ready'; pause; }

panel(){ banner; mkdir -p "$PANEL"; cd "$PANEL"; curl -fL -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz; tar -xzf panel.tar.gz; rm panel.tar.gz; cp -n .env.example .env; source $BASE/database.conf; read -rp 'Panel domain (e.g. panel.example.com): ' DOMAIN; read -rp 'Admin email: ' EMAIL; read -rp 'Timezone [Asia/Kolkata]: ' TZ; TZ=${TZ:-Asia/Kolkata}; printf 'PANEL_DOMAIN=%s\nADMIN_EMAIL=%s\nTIMEZONE=%s\n' "$DOMAIN" "$EMAIL" "$TZ" >$BASE/panel.conf; composer install --no-dev --optimize-autoloader --no-interaction; php artisan key:generate --force; php artisan p:environment:setup --author="$EMAIL" --url="https://$DOMAIN" --timezone="$TZ" --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-port=6379; php artisan p:environment:database --host=127.0.0.1 --port=3306 --database="$DB_NAME" --username="$DB_USER" --password="$DB_PASS"; php artisan migrate --seed --force; chown -R www-data:www-data "$PANEL"; ok 'Pterodactyl Panel installed'; pause; }

nginx_cfg(){ banner; source $BASE/panel.conf; cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server { listen 80; listen [::]:80; server_name $PANEL_DOMAIN; root $PANEL/public; index index.php; client_max_body_size 100M; location / { try_files \$uri \$uri/ /index.php?\$query_string; } location ~ \.php$ { include fastcgi_params; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; fastcgi_pass unix:/run/php/php8.3-fpm.sock; } location ~ /\.ht { deny all; } }
EOF
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf; rm -f /etc/nginx/sites-enabled/default; nginx -t; systemctl restart nginx; cat >/etc/systemd/system/pteroq.service <<EOF
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
systemctl daemon-reload; systemctl enable --now pteroq; ok 'Nginx and queue configured'; pause; }

admin(){ banner; cd "$PANEL"; php artisan p:user:make; ok 'Admin created'; pause; }

docker(){ banner; if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi; systemctl enable --now docker; ok 'Docker ready'; pause; }

wings(){ banner; mkdir -p "$WINGS"; curl -fL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$WA"; chmod +x /usr/local/bin/wings; cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=$WINGS
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable wings; ok 'Wings binary and service installed'; if [[ ! -f $WINGS/config.yml ]]; then warn 'Node config is required.'; echo 'In Pterodactyl Admin → Nodes → Create Node, copy the generated config to:'; echo "$WINGS/config.yml"; read -rp 'Paste Wings config now? [y/N]: ' A; if [[ $A =~ ^[Yy]$ ]]; then nano "$WINGS/config.yml"; fi; fi; [[ -f $WINGS/config.yml ]] && systemctl restart wings || true; pause; }

cloudflared(){ banner; apt-get install -y gpg; mkdir -p /usr/share/keyrings; curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg; echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' >/etc/apt/sources.list.d/cloudflared.list; apt-get update -y; apt-get install -y cloudflared; read -rp 'Cloudflare Tunnel token (leave blank to skip): ' TOKEN; if [[ -n "$TOKEN" ]]; then cloudflared service uninstall >/dev/null 2>&1 || true; cloudflared service install "$TOKEN"; systemctl enable --now cloudflared; ok 'Cloudflare Tunnel installed and started'; else warn 'Tunnel skipped'; fi; pause; }

ssl(){ banner; apt-get install -y certbot python3-certbot-nginx; source $BASE/panel.conf; read -rp 'SSL email: ' E; certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos --email "$E" --redirect; systemctl restart nginx; ok 'SSL installed'; pause; }

firewall(){ banner; ufw default deny incoming; ufw default allow outgoing; ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 2022/tcp; ufw --force enable; ok 'Firewall configured'; warn 'Add your game/allocation ports according to your Pterodactyl node configuration.'; pause; }

info(){ banner; echo -e "${C}${B}SYSTEM${R}"; echo "OS: $PRETTY_NAME"; echo "Kernel: $(uname -r)"; echo "CPU: $(nproc) cores"; echo "RAM:"; free -h; echo "Disk:"; df -h /; echo "IPv4: $(curl -4 -fsS --max-time 5 https://api.ipify.org || echo unknown)"; echo; for s in docker nginx mariadb redis-server php8.3-fpm pteroq wings cloudflared; do systemctl is-active --quiet "$s" 2>/dev/null && echo -e "${G}● RUNNING${R} $s" || echo -e "${RED}● STOPPED${R} $s"; done; pause; }

health(){ banner; bash -n "$0"; ok 'Bash syntax OK'; nginx -t; systemctl --failed --no-pager || true; echo; for s in docker nginx mariadb redis-server php8.3-fpm pteroq wings cloudflared; do printf '%-15s ' "$s"; systemctl is-active --quiet "$s" 2>/dev/null && echo -e "${G}OK${R}" || echo -e "${Y}N/A${R}"; done; pause; }

full(){ base; php; db; composer; panel; nginx_cfg; admin; docker; wings; cloudflared; ssl; firewall; health; banner; ok 'ANIME CLOUD V3 FULL INSTALLATION COMPLETE'; echo "Panel: https://$(awk -F= '/PANEL_DOMAIN/{print $2}' $BASE/panel.conf)"; echo "Wings config: $WINGS/config.yml"; echo "Log: $LOG"; pause; }

menu(){ while true; do banner; echo -e "${G}${B}[1]${R} 🚀 Automatic Full Installation"; echo -e "${G}[2]${R} Panel + Database"; echo -e "${G}[3]${R} Wings Automatic Setup"; echo -e "${C}[4]${R} ☁ Cloudflare Tunnel"; echo -e "${C}[5]${R} 🔒 Let's Encrypt SSL"; echo -e "${Y}[6]${R} 🐳 Docker"; echo -e "${Y}[7]${R} 🛡 Firewall"; echo -e "${BL}[8]${R} 🖥 System Information"; echo -e "${BL}[9]${R} 🔍 Health Check"; echo -e "${RED}[0]${R} Exit"; echo; read -rp '➜ Select [0-9]: ' X; case $X in 1) full;; 2) db; composer; panel; nginx_cfg;; 3) docker; wings;; 4) cloudflared;; 5) ssl;; 6) docker;; 7) firewall;; 8) info;; 9) health;; 0) exit 0;; *) warn 'Invalid option'; sleep 1;; esac; done; }
menu
