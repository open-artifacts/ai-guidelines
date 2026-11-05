#!/usr/bin/env bash
# Prepara uma VPS Ubuntu/Debian para receber o deploy deste projeto.
# Uso, como administrador:   sudo bash bootstrap-vps.sh '<chave publica ssh>'
#
# O que faz (e nada alem disso):
#   1. instala Docker (com Compose) e git, se faltarem (repositorio oficial do Docker);
#   2. cria o usuario "deploy": sem senha e sem sudo, apenas no grupo docker;
#   3. autoriza a chave publica informada nesse usuario;
#   4. imprime um resumo para colar de volta.
# Nao altera firewall, servicos, sites nem configuracoes existentes.
# Pode rodar mais de uma vez.
#
# Recusa-se a rodar, sem alterar nada, quando:
#   - o usuario "deploy" ja existe e tem poderes de administrador;
#   - o servidor encaminha pacotes (VPN/NAT) e o Docker ainda nao esta instalado,
#     porque o Docker mexe nas regras de rede. Para seguir mesmo assim:
#     sudo ALLOW_FORWARDING=1 bash bootstrap-vps.sh '<chave>'
#
# Para desfazer o acesso: sudo deluser --remove-home deploy
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l

DEPLOY_USER="${DEPLOY_USER:-deploy}"
PUBKEY="${1:-}"

die() { echo "ERRO: $*" >&2; exit 1; }

# --- Verificacoes (nada e alterado antes de todas passarem) ---------------
[ "$(id -u)" -eq 0 ] || die "rode como administrador (sudo)."

case "$PUBKEY" in
  ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-*) ;;
  *) die "informe a chave publica SSH como primeiro argumento." ;;
esac
[[ "$PUBKEY" != *$'\n'* ]] || die "a chave publica deve ter uma unica linha."

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
  ubuntu | debian) ;;
  *) die "sistema nao suportado (${ID:-desconhecido}). Use Ubuntu ou Debian." ;;
esac

if id "$DEPLOY_USER" >/dev/null 2>&1 \
  && id -nG "$DEPLOY_USER" | tr ' ' '\n' | grep -qxE 'sudo|admin|wheel|root'; then
  die "o usuario $DEPLOY_USER ja existe e tem poderes de administrador. Nada foi alterado."
fi

docker_missing=0
if [ "${SKIP_DOCKER_INSTALL:-0}" != 1 ] && ! command -v docker >/dev/null 2>&1; then
  docker_missing=1
fi
if [ "$docker_missing" = 1 ] && [ "${ALLOW_FORWARDING:-0}" != 1 ] \
  && [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" = 1 ]; then
  die "este servidor encaminha pacotes (VPN/NAT?) e instalar o Docker pode interferir nisso. Nada foi alterado. Se estiver tudo bem, rode de novo com: sudo ALLOW_FORWARDING=1 bash bootstrap-vps.sh '<chave>'"
fi

# --- Funcoes --------------------------------------------------------------
# Servidor recem-criado: o apt costuma estar ocupado com a atualizacao automatica.
# Em vez de adivinhar pelo nome dos processos (o servico "unattended-upgrades"
# fica sempre ativo e enganaria a checagem), tenta e repete enquanto o proprio
# apt reclamar do bloqueio, por ate 10 minutos. Qualquer outro erro para na hora.
apt_get() {
  local log start=$SECONDS announced=0
  log="$(mktemp)"
  until apt-get -o DPkg::Lock::Timeout=60 "$@" 2>&1 | tee "$log"; do
    if ! grep -qE '^E: (Could not get lock|Unable to acquire)' "$log"; then
      rm -f "$log"
      echo "ERRO: o apt falhou (veja a mensagem acima)." >&2
      return 1
    fi
    if [ $((SECONDS - start)) -ge 600 ]; then
      rm -f "$log"
      die "o apt segue ocupado ha 10 minutos. Tente de novo mais tarde."
    fi
    if [ "$announced" = 0 ]; then
      echo ">> Aguardando o apt ficar livre (atualizacao automatica em andamento)..."
      announced=1
    fi
    sleep 5
  done
  rm -f "$log"
}

install_docker() {
  echo ">> Instalando o Docker (repositorio oficial)..."
  apt_get update -q
  apt_get install -y -q ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  [ -n "$codename" ] || die "nao consegui identificar a versao do sistema."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $codename stable" \
    > /etc/apt/sources.list.d/docker.list
  apt_get update -q
  apt_get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# --- 1. Docker, Compose e git ---------------------------------------------
if [ "${SKIP_DOCKER_INSTALL:-0}" != 1 ]; then
  [ "$docker_missing" = 0 ] || install_docker
  if ! docker compose version >/dev/null 2>&1; then
    echo ">> Instalando o plugin Compose..."
    apt_get update -q
    apt_get install -y -q docker-compose-v2 || apt_get install -y -q docker-compose-plugin
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
  fi
fi
if ! command -v git >/dev/null 2>&1; then
  apt_get update -q
  apt_get install -y -q git
fi

# --- 2. Usuario de deploy: sem senha, sem sudo, no grupo docker ------------
getent group docker >/dev/null || groupadd docker
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo ">> Criando o usuario $DEPLOY_USER..."
  adduser --disabled-password --gecos "" "$DEPLOY_USER" >/dev/null
fi
usermod -aG docker "$DEPLOY_USER"

# --- 3. Chave publica autorizada -------------------------------------------
home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
grp="$(id -gn "$DEPLOY_USER")"
install -d -m 700 -o "$DEPLOY_USER" -g "$grp" "$home/.ssh"
touch "$home/.ssh/authorized_keys"
grep -qxF "$PUBKEY" "$home/.ssh/authorized_keys" || printf '%s\n' "$PUBKEY" >> "$home/.ssh/authorized_keys"
chown "$DEPLOY_USER:$grp" "$home/.ssh/authorized_keys"
chmod 600 "$home/.ssh/authorized_keys"

# --- 4. Resumo (somente leitura) para colar de volta ------------------------
ufw_state="ausente"
if command -v ufw >/dev/null 2>&1; then
  ufw_state="$(LC_ALL=C ufw status 2>/dev/null | head -1 | sed 's/^Status: //')"
  ufw_state="${ufw_state:-desconhecido} (nao alterado)"
fi
sshd_bin="$(command -v sshd || echo /usr/sbin/sshd)"
ssh_info="$("$sshd_bin" -T 2>/dev/null | grep -E '^(port|pubkeyauthentication|allowusers|allowgroups) ' | tr '\n' ';' || true)"
ip="$(curl -fsS -4 -m 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
ports="$(ss -ltnpH 'sport = :80 or sport = :443' 2>/dev/null | awk '{print $4, $6}' || true)"

echo
echo "=========== COLE ESTE RESUMO DE VOLTA ==========="
echo "Sistema:           ${PRETTY_NAME:-$ID}"
echo "IP publico:        $ip"
echo "SSH:               ${ssh_info:-indisponivel}"
echo "Docker:            $(docker --version 2>/dev/null || echo ausente)"
echo "Compose:           $(docker compose version 2>/dev/null || echo ausente)"
echo "Usuario de deploy: $DEPLOY_USER (grupos: $(id -nG "$DEPLOY_USER"))"
echo "Firewall ufw:      $ufw_state"
echo "Containers ativos: $(docker ps -q 2>/dev/null | wc -l)"
echo "Portas 80/443:     ${ports:-livres}"
echo "================================================="
