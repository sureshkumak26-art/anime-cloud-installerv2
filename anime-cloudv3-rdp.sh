#!/usr/bin/env bash
set -Eeuo pipefail

URL="https://raw.githubusercontent.com/sureshkumak26-art/anime-cloud-installerv2/main/anime-cloudv3-3d.sh"
WORK="/opt/anime-cloud/anime-cloudv3-rdp-runtime.sh"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash anime-cloudv3-rdp.sh"; exit 1; }
command -v curl >/dev/null 2>&1 || { apt-get update -y && apt-get install -y curl; }
command -v python3 >/dev/null 2>&1 || { apt-get update -y && apt-get install -y python3; }

mkdir -p /opt/anime-cloud
curl -fsSL "$URL" -o "$WORK"
chmod +x "$WORK"

python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()

credit='''\necho -e "${M}${B}╭────────────────────────────────────────────────────────╮${R}"\necho -e "${M}${B}│           ✦ Created by the mrhacker ✦                 │${R}"\necho -e "${M}${B}╰────────────────────────────────────────────────────────╯${R}"\n'''

if 'Created by the mrhacker' not in s:
    marker='banner(){'
    pos=s.find(marker)
    if pos >= 0:
        # Insert the credit immediately after the banner's closing brace.
        end=s.find('\n}\n', pos)
        if end >= 0:
            end += 3
            s=s[:end]+credit+s[end:]

rdp=r'''
container_tools(){
  while true; do
    banner
    echo -e "${C}${B}╭────────────── 📦 CONTAINER TOOLS ─────────────────────╮${R}"
    echo -e "│ ${G}[1]${R} 🖥️  INSTALL LINUX RDP (XRDP)"
    echo -e "│ ${G}[2]${R} 🐳 RDP GUI DOCKER CONTAINER"
    echo -e "│ ${G}[3]${R} 🔍 RDP STATUS"
    echo -e "│ ${G}[4]${R} 🛑 STOP RDP"
    echo -e "│ ${G}[5]${R} 🗑️  REMOVE RDP"
    echo -e "│ ${RED}[0]${R} ↩ BACK"
    echo -e "${C}${B}╰────────────────────────────────────────────────────────╯${R}"
    echo
    read -rp "Container Tools > " r
    case "$r" in
      1)
        apt-get update -y
        apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11
        systemctl enable --now xrdp
        ufw allow 3389/tcp 2>/dev/null || true
        echo -e "${G}${B}✔ Linux RDP installed. Port: 3389${R}"
        echo "Create a user with: adduser <username>"
        pause;;
      2)
        command -v docker >/dev/null 2>&1 || { warn "Docker is required."; pause; continue; }
        read -rp "Container name [anime-rdp]: " NAME
        NAME="${NAME:-anime-rdp}"
        read -rp "Host port [3389]: " PORT
        PORT="${PORT:-3389}"
        docker rm -f "$NAME" >/dev/null 2>&1 || true
        docker run -d --name "$NAME" --restart unless-stopped -p "${PORT}:3389" dorowu/ubuntu-desktop-lxde-vnc:latest
        ufw allow "${PORT}/tcp" 2>/dev/null || true
        echo -e "${G}${B}✔ RDP GUI container started.${R}"
        echo "Container: $NAME | Port: $PORT"
        pause;;
      3)
        systemctl is-active --quiet xrdp 2>/dev/null && echo -e "${G}✔ xrdp RUNNING${R}" || echo -e "${RED}✘ xrdp STOPPED${R}"
        docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}' 2>/dev/null
        pause;;
      4)
        systemctl disable --now xrdp 2>/dev/null || true
        docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'anime-rdp|rdp' | xargs -r docker stop
        warn "RDP stopped."
        pause;;
      5)
        systemctl disable --now xrdp 2>/dev/null || true
        apt-get purge -y xrdp 2>/dev/null || true
        docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E 'anime-rdp|rdp' | xargs -r docker rm -f
        warn "RDP components removed."
        pause;;
      0) return;;
      *) warn "Invalid option."; sleep 1;;
    esac
  done
}
'''

if 'container_tools(){' not in s:
    marker='menu(){'
    pos=s.find(marker)
    if pos < 0:
        raise SystemExit('menu() not found')
    s=s[:pos]+rdp+'\n'+s[pos:]

# Replace option 7 (Container Tools) to open the RDP/container submenu.
s=s.replace('7) docker; pause;;','7) container_tools;;',1)
s=s.replace('7) docker; pause;','7) container_tools;',1)

p.write_text(s)
PY

bash -n "$WORK"
echo "Anime Cloud V3 RDP edition: syntax OK"
exec "$WORK"
