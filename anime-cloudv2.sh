#!/usr/bin/env bash
set -Eeuo pipefail

# Anime Cloud Installer V4
# Pterodactyl Panel + Wings + Docker + Cloudflare + SSL

R='\033[0m'; B='\033[1m'; C='\033[36m'; G='\033[32m'; Y='\033[33m'; M='\033[35m'; RED='\033[31m'; W='\033[97m'; BL='\033[34m'
BASE=/root/anime-cloud
PANEL=/var/www/pterodactyl
mkdir -p "$BASE"
LOG="$BASE/install.log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo -e "${RED}✘ Error on line $LINENO. Log: $LOG${R}"' ERR
banner(){ clear; echo -e "${M}${B}╔════════════════════════════════════════════════════╗${R}"; echo -e "${M}${B}║              ANIME CLOUD INSTALLER                 ║${R}"; echo -e "${C}${B}║       PTERODACTYL • WINGS • CLOUDFLARE             ║${R}"; echo -e "${M}${B}╚════════════════════════════════════════════════════╝${R}"; echo; }
ok(){ echo -e "${G}✔${R} $*"; }
warn(){ echo -e "${Y}⚠${R} $*"; }
die(){ echo -e "${RED}✘${R} $*"; exit 1; }
pause(){ echo; read -rp "Press ENTER to continue..." _; }
root(){ [[ $EUID -eq 0 ]] || die "Run as root."; }
system_deps(){ banner; apt-get update -y; apt-get install -y curl wget git unzip tar gzip ca-certificates gnupg lsb-release software-properties-common apt-transport-https jq sudo nano vim ufw cron openssl nginx; ok "System dependencies installed"; pause; }
php83(){ banner; . /etc/os-release; if [[ $ID == ubuntu ]]; then apt-get install -y software-properties-common; add-apt-repository -y ppa:ondrej/php || true; else apt-get install -y lsb-release ca-certificates apt-transport-https; curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/php.gpg; echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list; fi; apt-get update -y; apt-get install -y php8.3 php8.3-cli php8.3-common php8.3-fpm php8.3-gd php8.3-mysql php8.3-mbstring php8.3-bcmath php8.3-xml php8.3-curl php8.3-zip php8.3-opcache; systemctl enable --now php8.3-fpm; sed -i 's/^memory_limit = .*/memory_limit = 512M/' /etc/php/8.3/fpm/php.ini; systemctl restart php8.3-fpm; ok "PHP 8.3 installed"; pause; }
db_redis(){ banner; apt-get install -y mariadb-server mariadb-client redis-server; systemctl enable --now mariadb redis-server; DBPASS=$(openssl rand -hex 24); mysql -uroot <<SQL
CREATE DATABASE IF NOT EXISTS panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
ALTER USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
printf 'DB_HOST=127.0.0.1\nDB_PORT=3306\nDB_DATABASE=panel\nDB_USERNAME=pterodactyl\nDB_PASSWORD=%s\n' "$DBPASS" > "$BASE/database.env"; chmod 600 "$BASE/database.env"; ok "MariaDB + Redis installed and database created"; pause; }
composer_install(){ banner; if ! command -v composer >/dev/null; then curl -fsSL https://getcomposer.org/installer -o /tmp/composer.php; php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer; rm -f /tmp/composer.php; fi; composer --version; ok "Composer ready"; pause; }
panel_download(){ banner; mkdir -p "$PANEL"; cd "$PANEL"; curl -fL -o panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz; tar -xzf panel.tar.gz; rm -f panel.tar.gz; cp -n .env.example .env || true; COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction; php artisan key:generate --force; chown -R www-data:www-data "$PANEL"; chmod -R 755 storage bootstrap/cache; ok "Pterodactyl Panel downloaded"; pause; }
panel_config(){ banner; [[ -f "$PANEL/artisan" ]] || die "Install Panel first."; source "$BASE/database.env"; read -rp "Panel domain (panel.example.com): " DOMAIN; read -rp "Timezone [Asia/Kolkata]: " TZ; TZ=${TZ:-Asia/Kolkata}; read -rp "Admin email: " EMAIL; [[ -n $DOMAIN && -n $EMAIL ]] || die "Domain and email required"; cat > "$BASE/panel.env" <<CFG
DOMAIN=$DOMAIN
EMAIL=$EMAIL
TZ=$TZ
CFG
cd "$PANEL"; php artisan p:environment:setup --author="$EMAIL" --url="https://$DOMAIN" --timezone="$TZ" --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-port=6379 --redis-database=0; php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password="$DB_PASSWORD"; php artisan migrate --seed --force; chown -R www-data:www-data "$PANEL"; ok "Panel configured"; pause; }
nginx_config(){ banner; [[ -f "$BASE/panel.env" ]] || die "Configure Panel first."; source "$BASE/panel.env"; cat >/etc/nginx/sites-available/pterodactyl.conf <<NGINX
server {
 listen 80;
 listen [::]:80;
 server_name $DOMAIN;
 root $PANEL/public;
 index index.php;
 client_max_body_size 100M;
 location / { try_files \$uri \$uri/ /index.php?\$query_string; }
 location ~ \.php$ { include fastcgi_params; fastcgi_pass unix:/run/php/php8.3-fpm.sock; fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name; }
 location ~ /\.ht { deny all; }
}
NGINX
ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf; rm -f /etc/nginx/sites-enabled/default; nginx -t; systemctl enable --now nginx; systemctl reload nginx; ok "Nginx configured"; pause; }
admin_user(){ banner; cd "$PANEL"; php artisan p:user:make; pause; }
queue_worker(){ banner; cat >/etc/systemd/system/pteroq.service <<'UNIT'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now pteroq; ok "Queue worker enabled"; pause; }
docker_install(){ banner; command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh; systemctl enable --now docker; docker --version; ok "Docker ready"; pause; }
wings_install(){ banner; mkdir -p /etc/pterodactyl; ARCH=$(uname -m); case $ARCH in x86_64) A=amd64;; aarch64|arm64) A=arm64;; *) die "Unsupported architecture: $ARCH";; esac; curl -fL -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$A"; chmod +x /usr/local/bin/wings; cat >/etc/systemd/system/wings.service <<'UNIT'
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service
[Service]
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable wings; ok "Wings installed"; warn "Create a Node in Panel and save its config as /etc/pterodactyl/config.yml"; pause; }
cloudflare_dns(){ banner; read -rsp "Cloudflare API Token: " TOKEN; echo; read -rp "Zone domain (example.com): " ZONE; read -rp "DNS hostname (panel.example.com): " HOST; IP=$(curl -4 -fsS https://api.ipify.org); Z=$(curl -fsS "https://api.cloudflare.com/client/v4/zones?name=$ZONE&status=active&per_page=1" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json'); ZID=$(echo "$Z"|jq -r '.result[0].id // empty'); [[ -n $ZID ]] || die "Cloudflare zone not found or token lacks permission."; OLD=$(curl -fsS "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records?type=A&name=$HOST" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json'); RID=$(echo "$OLD"|jq -r '.result[0].id // empty'); DATA=$(jq -n --arg n "$HOST" --arg c "$IP" '{type:"A",name:$n,content:$c,ttl:1,proxied:false}'); if [[ -n $RID ]]; then R=$(curl -fsS -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records/$RID" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data "$DATA"); else R=$(curl -fsS -X POST "https://api.cloudflare.com/client/v4/zones/$ZID/dns_records" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data "$DATA"); fi; [[ $(echo "$R"|jq -r .success) == true ]] || die "Cloudflare DNS update failed."; printf 'ZONE_ID=%s\nHOST=%s\n' "$ZID" "$HOST" > "$BASE/cloudflare.env"; chmod 600 "$BASE/cloudflare.env"; ok "Cloudflare DNS: $HOST -> $IP"; pause; }
ssl_install(){ banner; [[ -f "$BASE/panel.env" ]] || die "Configure Panel first."; source "$BASE/panel.env"; apt-get install -y certbot python3-certbot-nginx; read -rp "SSL email [$EMAIL]: " SE; SE=${SE:-$EMAIL}; certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$SE" --redirect; ok "Let's Encrypt SSL installed"; pause; }
cf_ssl(){ banner; [[ -f "$BASE/cloudflare.env" ]] || die "Configure Cloudflare DNS first."; source "$BASE/cloudflare.env"; read -rsp "Cloudflare API Token: " TOKEN; echo; echo '[1] off [2] flexible [3] full [4] strict'; read -rp 'Select: ' N; case $N in 1) MODE=off;;2) MODE=flexible;;3) MODE=full;;4) MODE=strict;;*) die 'Invalid option';; esac; R=$(curl -fsS -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data "{\"value\":\"$MODE\"}"); [[ $(echo "$R"|jq -r .success) == true ]] || die "Cloudflare SSL update failed"; ok "Cloudflare SSL mode: $MODE"; pause; }
firewall(){ banner; apt-get install -y ufw; ufw default deny incoming; ufw default allow outgoing; for p in 22 80 443 2022 8080 8443; do ufw allow "$p/tcp"; done; ufw --force enable; ufw status verbose; ok "Firewall configured"; warn "Open your required game/allocation ports separately."; pause; }
system_info(){ banner; echo -e "${C}${B}SYSTEM${R}"; hostnamectl 2>/dev/null || true; echo; echo -e "${C}${B}CPU / RAM${R}"; nproc; free -h; echo; echo -e "${C}${B}DISK${R}"; df -hT; echo; echo -e "${C}${B}IP${R}"; curl -4 -fsS https://api.ipify.org || true; echo; ip -br addr; echo; echo -e "${C}${B}SERVICES${R}"; for s in nginx mariadb redis-server php8.3-fpm docker pteroq wings; do systemctl is-active --quiet "$s" && echo -e "${G}● RUNNING${R} $s" || echo -e "${RED}● STOPPED/NOT INSTALLED${R} $s"; done; pause; }
full(){ system_deps; php83; db_redis; composer_install; panel_download; panel_config; nginx_config; queue_worker; docker_install; wings_install; cloudflare_dns; ssl_install; firewall; banner; ok "FULL INSTALLATION COMPLETE"; warn "Create a Pterodactyl Node and put config.yml in /etc/pterodactyl/ before starting Wings."; pause; }
menu(){ while true; do banner; echo -e "${G}${B}[1]${R} System Dependencies"; echo -e "${G}${B}[2]${R} PHP 8.3"; echo -e "${G}${B}[3]${R} MariaDB + Redis + Database"; echo -e "${G}${B}[4]${R} Composer"; echo -e "${G}${B}[5]${R} Install Panel"; echo -e "${G}${B}[6]${R} Configure Panel"; echo -e "${G}${B}[7]${R} Nginx"; echo -e "${G}${B}[8]${R} Create Admin"; echo -e "${G}${B}[9]${R} Queue Worker"; echo -e "${BL}${B}[10]${R} Docker"; echo -e "${BL}${B}[11]${R} Wings"; echo -e "${M}${B}[12]${R} Cloudflare DNS"; echo -e "${M}${B}[13]${R} Let's Encrypt SSL"; echo -e "${M}${B}[14]${R} Cloudflare SSL Mode"; echo -e "${Y}${B}[15]${R} Firewall"; echo -e "${C}${B}[16]${R} System Information"; echo -e "${Y}${B}[17]${R} FULL INSTALLATION"; echo -e "${RED}${B}[0]${R} Exit"; echo; read -rp 'Select [0-17]: ' X; case $X in 1)system_deps;;2)php83;;3)db_redis;;4)composer_install;;5)panel_download;;6)panel_config;;7)nginx_config;;8)admin_user;;9)queue_worker;;10)docker_install;;11)wings_install;;12)cloudflare_dns;;13)ssl_install;;14)cf_ssl;;15)firewall;;16)system_info;;17)full;;0)exit 0;;*)warn 'Invalid option'; sleep 1;; esac; done; }
root
menu
