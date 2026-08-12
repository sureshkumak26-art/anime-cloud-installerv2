#!/usr/bin/env bash
set -Eeuo pipefail
R='\033[0m'; C='\033[96m'; G='\033[92m'; Y='\033[93m'; RED='\033[91m'; B='\033[1m'
ok(){ echo -e "${G}✔${R} $*"; }; warn(){ echo -e "${Y}⚠${R} $*"; }; pause(){ read -rp 'Press ENTER to continue...'; }
rdp(){
  clear
  echo -e "${C}${B}Installing RDP...${R}"
  apt-get update -y
  apt-get install -y xrdp xfce4 xfce4-goodies dbus-x11
  systemctl enable --now xrdp
  command -v ufw >/dev/null 2>&1 && ufw allow 3389/tcp || true
  ok 'RDP installed — port 3389'
  pause
}
vscode(){
  clear
  command -v docker >/dev/null 2>&1 || { warn 'Docker is not installed. Install Docker first.'; pause; return; }
  read -rp 'Container name [vscode]: ' NAME; NAME=${NAME:-vscode}
  read -rp 'Host port [8080]: ' PORT; PORT=${PORT:-8080}
  read -rsp 'VS Code password [123456]: ' PASS; echo; PASS=${PASS:-123456}
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -p "${PORT}:8080" -e PASSWORD="$PASS" --restart unless-stopped ghcr.io/coder/code-server:latest
  command -v ufw >/dev/null 2>&1 && ufw allow "${PORT}/tcp" || true
  ok "VS Code Server started — http://SERVER-IP:${PORT}"
  pause
}
menu(){
  while true; do
    clear
    echo -e "${C}${B}╔══════════════════════════════════════════════╗${R}"
    echo -e "${C}${B}║       ANIME CLOUD — CONTAINER TOOLS          ║${R}"
    echo -e "${C}${B}║           ✦ by the mrhacker ✦                ║${R}"
    echo -e "${C}${B}╚══════════════════════════════════════════════╝${R}"
    echo
    echo -e "${G}[1]${R} 🖥️ RDP"
    echo -e "${G}[2]${R} 💻 VS CODE SERVER"
    echo
    echo -e "${RED}[0]${R} ↩ Back"
    echo
    read -rp 'Container Tools > ' choice
    case "$choice" in
      1) rdp;;
      2) vscode;;
      0) exit 0;;
      *) warn 'Invalid option'; sleep 1;;
    esac
  done
}
[[ $EUID -eq 0 ]] || { echo 'Run as root.'; exit 1; }
menu
