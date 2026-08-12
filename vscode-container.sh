#!/usr/bin/env bash
set -Eeuo pipefail
NAME="vscode"
PORT="8080"
read -rp "Container name [$NAME]: " n; NAME="${n:-$NAME}"
read -rp "Host port [$PORT]: " p; PORT="${p:-$PORT}"
read -rsp "VS Code password [123456]: " PASS; echo; PASS="${PASS:-123456}"
command -v docker >/dev/null 2>&1 || { echo 'Docker is required.'; exit 1; }
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "${PORT}:8080" -e PASSWORD="$PASS" --restart unless-stopped ghcr.io/coder/code-server:latest
echo "VS Code Server started: http://SERVER-IP:${PORT}"
