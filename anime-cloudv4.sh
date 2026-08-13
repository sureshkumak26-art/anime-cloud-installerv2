#!/usr/bin/env bash
set -Eeuo pipefail
R='\033[0m'; C='\033[96m'; G='\033[92m'; Y='\033[93m'; M='\033[95m'; RED='\033[91m'; B='\033[1m'
BASE=/opt/anime-cloud; PANEL=/var/www/pterodactyl; WINGS=/etc/pterodactyl; LOG=$BASE/v4-install.log
mkdir -p "$BASE"; touch "$LOG"; exec > >(tee -a "$LOG") 2>&1
ok(){ echo -e "${G}✔${R} $*"; }; warn(){ echo -e "${Y}⚠${R} $*"; }; die(){ echo -e "${RED}✘${R} $*"; exit 1; }; pause(){ read -rp 'Press ENTER to continue...'; }
root(){ [[ $EUID -eq 0 ]] || die 'Run as root.'; }
oscheck(){ source /etc/os-release; [[ "$ID" == ubuntu || "$ID" == debian ]] || die 'Ubuntu/Debian required.'; ok "OS: $PRETTY_NAME"; }
banner(){ clear; echo -e "${C}${B}╔════════════════════════════════════════════════════╗${R}"; echo -e "${C}${B}║              ANIME CLOUD V4                        ║${R}"; echo -e "${C}${B}║ PTERODACTYL • WINGS • CLOUDFLARE • CONTAINERS      ║${R}"; echo -e "${M}${B}║                 ✦ by the mrhacker ✦                ║${R}"; echo -e "${C}${B}╚════════════════════════════════════════════════════╝${R}"; }
info(){ banner; echo -e "${M}${B}SYSTEM INFORMATION${R}"; echo "Hostname : $(hostname)"; echo "Kernel   : $(uname -r)"; echo "CPU      : $(nproc) cores"; echo "RAM      : $(free -h|awk '/Mem:/{print $3" / "$2}')"; echo "Disk     : $(df -h /|awk 'NR==2{print $3" / "$2" ("$5")"}')"; echo "IPv4     : $(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo unknown)"; for s in docker nginx mariadb redis-server pteroq wings cloudflared xrdp; do systemctl is-active --quiet "$s" 2>/dev/null && echo -e "${G}● RUNNING${R} $s" || echo -e "${RED}● STOPPED${R} $s"; done; pause; }
deps(){ apt-get update -y; DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git unzip tar gzip ca-certificates gnupg lsb-release software-properties-common apt-transport-https jq mariadb-server redis-server nginx certbot python3-certbot-nginx ufw cron openssl; systemctl enable --now mariadb redis-server nginx; ok 'System dependencies installed.'; }
php83(){ source /etc/os-release; if [[ "$ID" == ubuntu ]]; then apt-get install -y software-properties-common; add-apt-repository -y ppa:ondrej/php || true; else echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list; curl -fsSL https://packages.sury.org/php/apt.gpg|gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/php.gpg; fi; apt-get update -y; apt-get install -y php8.3 php8.3-cli php8.3-fpm php8.3-common php8.3-mysql php8.3-gd php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-opcache; systemctl enable --now php8.3-fpm; ok 'PHP 8.3 installed.'; }
composer(){ command -v composer >/dev/null || { curl -fsSL https://getcomposer.org/installer -o /tmp/composer.php; php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer; rm -f /tmp/composer.php; }; ok 'Composer ready.'; }
db(){ local p; p=$(openssl rand -hex 24); mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS panel;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$p';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$p';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
cat >$BASE/database.env <<EOF
DB_DATABASE=panel
DB_USERNAME=pterodactyl
DB_PASSWORD=$p
DB_HOST=127.0.0.1
DB_PORT=3306
EOF
chmod 600 $BASE/database.env; ok 'MariaDB database created.'; }
panel(){ mkdir -p "$PANEL"; cd "$PANEL"; curl -fL https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz -o panel.tar.gz; tar -xzf panel.tar.gz; rm -f panel.tar.gz; cp -n .env.example .env || true; composer install --no-dev --optimize-autoloader --no-interaction; php artisan key:generate --force; chown -R www-data:www-data "$PANEL"; ok 'Pterodactyl Panel installed.'; }
panelcfg(){ read -rp 'Panel domain: ' DOMAIN; read -rp 'Admin email: ' EMAIL; [[ -n "$DOMAIN" && -n "$EMAIL" ]] || die 'Domain and email are required.'; source "$BASE/database.env"; cd "$PANEL"; php artisan p:environment:setup --author="$EMAIL" --url="https://$DOMAIN" --timezone=Asia/Kolkata --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-port=6379; php artisan p:environment:database --host="$DB_HOST" --port="$DB_PORT" --database="$DB_DATABASE" --username="$DB_USERNAME" --password="$DB_PASSWORD"; php artisan migrate --seed --force; printf 'DOMAIN=%s\nEMAIL=%s\n' "$DOMAIN" "$EMAIL" >$BASE/panel.env; chmod 600 $BASE/panel.env; chown -R www-data:www-data "$PANEL"; ok 'Panel configured.'; }
nginx_cfg(){ source "$BASE/panel.env"; cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
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
docker_install(){ command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh; systemctl enable --now docker; ok 'Docker ready.'; }
wings(){ mkdir -p "$WINGS"; case $(uname -m) in x86_64) b=wings_linux_amd64;; aarch64|arm64) b=wings_linux_arm64;; *) die 'Unsupported architecture.';; esac; curl -fL "https://github.com/pterodactyl/wings/releases/latest/download/$b" -o /usr/local/bin/wings; chmod +x /usr/local/bin/wings; cat >/etc/systemd/system/wings.service <<EOF
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
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable wings; [[ -f "$WINGS/config.yml" ]] && systemctl restart wings || warn "Wings installed. Create Node config at $WINGS/config.yml from your Panel."; ok 'Wings installed.'; }
cloudflare(){ read -rsp 'Cloudflare Tunnel token (ENTER to cancel): ' T; echo; [[ -n "$T" ]] || { warn 'Tunnel cancelled.'; return; }; case $(uname -m) in x86_64) p=cloudflared-linux-amd64.deb;; aarch64|arm64) p=cloudflared-linux-arm64.deb;; *) die 'Unsupported architecture.';; esac; curl -fL "https://github.com/cloudflare/cloudflared/releases/latest/download/$p" -o /tmp/cloudflared.deb; apt-get install -y /tmp/cloudflared.deb; rm -f /tmp/cloudflared.deb; cloudflared service uninstall >/dev/null 2>&1 || true; cloudflared service install "$T"; systemctl enable --now cloudflared; ok 'Cloudflare Tunnel enabled.'; }
ssl(){ [[ -f "$BASE/panel.env" ]] || die 'Configure Panel first.'; source "$BASE/panel.env"; read -rp "SSL email [$EMAIL]: " E; E=${E:-$EMAIL}; certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$E" --redirect; ok 'SSL configured.'; }
firewall(){ ufw default deny incoming; ufw default allow outgoing; ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 2022/tcp; ufw allow 3389/tcp; ufw allow 8080/tcp; ufw --force enable; ok 'Firewall configured.'; }
admin(){ cd "$PANEL"; php artisan p:user:make; }
rdp(){ apt-get update -y; apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11; echo 'startxfce4' >/etc/xrdp/startwm.sh; chmod +x /etc/xrdp/startwm.sh; systemctl enable --now xrdp; ufw allow 3389/tcp 2>/dev/null || true; ok 'Linux RDP installed on port 3389.'; }
rdp_docker(){ docker_install; read -rp 'RDP container name [anime-rdp]: ' N; N=${N:-anime-rdp}; read -rp 'RDP host port [3389]: ' P; P=${P:-3389}; docker rm -f "$N" >/dev/null 2>&1 || true; docker run -d --name "$N" --restart unless-stopped -p "$P:3389" dorowu/ubuntu-desktop-lxde-vnc:latest; ufw allow "$P/tcp" 2>/dev/null || true; ok "RDP Docker container started on port $P."; }
vscode(){ docker_install; read -rp 'Container name [vscode]: ' N; N=${N:-vscode}; read -rp 'Host port [8080]: ' P; P=${P:-8080}; read -rsp 'VS Code password: ' PASS; echo; [[ -n "$PASS" ]] || die 'Password required.'; docker rm -f "$N" >/dev/null 2>&1 || true; docker run -d --name "$N" --restart unless-stopped -p "$P:8080" -e PASSWORD="$PASS" ghcr.io/coder/code-server:latest; ufw allow "$P/tcp" 2>/dev/null || true; ok "VS Code Server: http://SERVER-IP:$P"; }
container_tools(){ while true; do banner; echo -e "${M}${B}CONTAINER TOOLS${R}"; echo '[1] 🖥️ RDP'; echo '[2] 💻 VS CODE SERVER'; echo '[0] ↩ Back'; read -rp 'Container Tools > ' x; case "$x" in 1) rdp;; 2) vscode;; 0) return;; *) warn 'Invalid option.';; esac; pause; done; }
vps_manager(){ wget -qO /tmp/anime-cloud-vm.sh https://raw.githubusercontent.com/sureshkumak26-art/vm/main/anime-cloud-vm-manager.sh; chmod +x /tmp/anime-cloud-vm.sh; /tmp/anime-cloud-vm.sh; }
full(){ banner; read -rp 'Start FULL AUTO installation? [y/N]: ' a; [[ "$a" =~ ^[Yy]$ ]] || return; deps; php83; composer; db; panel; panelcfg; nginx_cfg; queue; docker_install; wings; cloudflare; firewall; admin; ok 'Anime Cloud V4 full installation finished.'; }
menu(){ while true; do banner; echo -e "${G}${B}DEPLOYMENT & SERVICES${R}"; echo '[1] 🖥️ System Detection'; echo '[2] 🦎 Pterodactyl Panel'; echo '[3] ⚙️ Wings'; echo '[4] 🐳 Docker'; echo '[5] 🗄️ MariaDB + Redis'; echo '[6] 📊 System Information'; echo '[7] 📦 Container Tools'; echo '[8] ☁️ Cloudflare Tunnel'; echo '[9] 🖥️ VPS Manager'; echo '[10] 🔒 SSL'; echo '[11] 🛡️ Firewall'; echo '[12] ❤️ Health Check'; echo '[13] 🚀 FULL AUTO INSTALL'; echo '[0] ⏻ Exit'; echo; read -rp 'Anime Cloud V4 > ' o; case "$o" in 1) oscheck; pause;; 2) deps; php83; composer; db; panel; panelcfg; nginx_cfg; queue; admin; pause;; 3) docker_install; wings; pause;; 4) docker_install; pause;; 5) apt-get update -y; apt-get install -y mariadb-server redis-server; systemctl enable --now mariadb redis-server; ok 'MariaDB + Redis ready.'; pause;; 6|12) info;; 7) container_tools;; 8) cloudflare; pause;; 9) vps_manager;; 10) ssl; pause;; 11) firewall; pause;; 13) full; pause;; 0) clear; exit 0;; *) warn 'Invalid option.'; sleep 1;; esac; done; }
root; oscheck; menu
