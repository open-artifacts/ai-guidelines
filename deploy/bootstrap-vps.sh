#!/usr/bin/env bash
# Prepara uma VPS Ubuntu/Debian para receber o deploy deste projeto.
# Uso, como administrador:   sudo bash bootstrap-vps.sh '<chave publica ssh>'
#
# O que faz (e nada alem disso):
#   1. instala Docker (com Compose) e git, se faltarem;
#   2. cria o usuario "deploy": sem senha e sem sudo, apenas no grupo docker;
#   3. autoriza a chave publica informada nesse usuario;
#   4. se o firewall ufw estiver ativo, libera as portas 80 e 443;
#   5. imprime um resumo para colar de volta.
# Nao altera servicos, sites nem configuracoes existentes. Pode rodar mais de uma vez.
#
# Para desfazer o acesso: sudo deluser --remove-home deploy
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
PUBKEY="${1:-}"

[ "$(id -u)" -eq 0 ] || { echo "Rode como administrador (sudo)." >&2; exit 1; }

case "$PUBKEY" in
  ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-*) ;;
  *) echo "Informe a chave publica SSH como primeiro argumento." >&2; exit 1 ;;
esac
[[ "$PUBKEY" != *$'\n'* ]] || { echo "A chave publica deve ter uma unica linha." >&2; exit 1; }

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu | debian) ;;
  *) echo "Sistema nao suportado: ${ID:-desconhecido}. Use Ubuntu ou Debian." >&2; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive

# 1. Docker, Compose e git
if [ "${SKIP_DOCKER_INSTALL:-0}" != 1 ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo ">> Instalando o Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl
    curl -fsSL https://get.docker.com | sh
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo ">> Instalando o plugin Compose..."
    apt-get update -qq
    apt-get install -y -qq docker-compose-plugin || apt-get install -y -qq docker-compose-v2
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
fi
command -v git >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq git; }

# 2. Usuario de deploy: sem senha, sem sudo, no grupo docker
getent group docker >/dev/null || groupadd docker
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo ">> Criando o usuario $DEPLOY_USER..."
  adduser --disabled-password --gecos "" "$DEPLOY_USER" >/dev/null
fi
usermod -aG docker "$DEPLOY_USER"

# 3. Chave publica autorizada
home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
touch "$home/.ssh/authorized_keys"
grep -qxF "$PUBKEY" "$home/.ssh/authorized_keys" || printf '%s\n' "$PUBKEY" >> "$home/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "$home/.ssh/authorized_keys"
chmod 600 "$home/.ssh/authorized_keys"

# 4. Firewall local (ufw), apenas se ja estiver ativo
ufw_state="ausente"
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw_state="ativo (portas 80 e 443 liberadas)"
  else
    ufw_state="inativo"
  fi
fi

# 5. Resumo para colar de volta
ip="$(curl -fsS -4 -m 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
ports="$(ss -ltnpH 'sport = :80 or sport = :443' 2>/dev/null | awk '{print $4, $6}' || true)"
echo
echo "=========== COLE ESTE RESUMO DE VOLTA ==========="
echo "Sistema:           ${PRETTY_NAME:-$ID}"
echo "IP publico:        $ip"
echo "Docker:            $(docker --version 2>/dev/null || echo ausente)"
echo "Compose:           $(docker compose version 2>/dev/null || echo ausente)"
echo "Usuario de deploy: $DEPLOY_USER (grupos: $(id -nG "$DEPLOY_USER"))"
echo "Firewall ufw:      $ufw_state"
echo "Containers ativos: $(docker ps -q 2>/dev/null | wc -l)"
echo "Portas 80/443:     ${ports:-livres}"
echo "================================================="
