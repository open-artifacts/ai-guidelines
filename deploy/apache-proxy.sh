#!/usr/bin/env bash
# Publica a API deste projeto (que ouve so em 127.0.0.1:3000) por HTTPS no Apache
# que ja atende o servidor, com um nome proprio e certificado do certbot.
# Uso, como administrador:   sudo bash apache-proxy.sh <dominio> [email]
#   [email] so e preciso se o certbot ainda nao tem conta neste servidor.
#
# O que faz (e nada alem disso):
#   1. habilita os modulos proxy e proxy_http do Apache (nao ligam nenhum proxy aberto);
#   2. cria UM virtual host novo, so para <dominio>, sem tocar nos sites existentes;
#   3. pede o certificado ao certbot e ativa o HTTPS so para esse nome;
#   4. testa https://<dominio>/api/health e imprime um resumo.
#
# Antes de mudar qualquer coisa confere: Apache e certbot instalados, API
# respondendo, DNS do <dominio> apontando para este servidor. Se o Apache
# recusar a configuracao nova, ou se ela mudar o site padrao do servidor,
# desfaz sozinho e nao recarrega nada.
#
# O arquivo comeca com "zz-" de proposito: o Apache usa o primeiro virtual host
# como padrao para nomes desconhecidos, e este nao pode ser o primeiro.
#
# Para desfazer:
#   sudo a2dissite zz-ai-guidelines-api zz-ai-guidelines-api-le-ssl
#   sudo rm /etc/apache2/sites-available/zz-ai-guidelines-api*.conf
#   sudo certbot delete --cert-name <dominio>
#   sudo systemctl reload apache2
# Os modulos proxy e proxy_http continuam habilitados (nao abrem proxy aberto). So se
# mais nada neste servidor os usa: sudo a2dismod proxy_http proxy && sudo systemctl restart apache2
set -euo pipefail

SITE="zz-ai-guidelines-api"
CONF="/etc/apache2/sites-available/$SITE.conf"
API_PORT="${API_PORT:-3000}"
DOMAIN="${1:-}"
EMAIL="${2:-}"

die() { echo "ERRO: $*" >&2; exit 1; }

# --- Verificacoes (nada e alterado antes de todas passarem) ---------------
[ "$(id -u)" -eq 0 ] || die "rode como administrador (sudo)."
[[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] \
  || die "informe o dominio como primeiro argumento (ex.: api.exemplo.org, em minusculas)."
[[ "$API_PORT" =~ ^[0-9]{2,5}$ ]] || die "API_PORT invalida: $API_PORT"
API="http://127.0.0.1:$API_PORT"
command -v apache2ctl >/dev/null 2>&1 || die "Apache nao encontrado."
if [ "${SKIP_CERTBOT:-0}" != 1 ]; then
  command -v certbot >/dev/null 2>&1 || die "certbot nao encontrado."
  [ -z "$EMAIL" ] || [[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || die "e-mail invalido: $EMAIL"
  if [ -z "$EMAIL" ] && [ -z "$(ls -A /etc/letsencrypt/accounts 2>/dev/null)" ]; then
    die "o certbot ainda nao tem conta neste servidor. Rode de novo informando um e-mail: sudo bash apache-proxy.sh $DOMAIN voce@exemplo.org"
  fi
fi
if [ -e "$CONF" ] && ! grep -qxF "    ServerName $DOMAIN" "$CONF"; then
  die "$CONF ja existe para outro nome. Nada foi alterado."
fi
curl -fsS -m 5 "$API/api/health" 2>/dev/null | grep -q '"ok":true' \
  || die "a API nao responde em $API/api/health. Suba-a antes (docker compose up -d)."

if [ "${SKIP_DNS_CHECK:-0}" != 1 ]; then
  dns_ip="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
  server_ip="$(curl -fsS -4 -m 5 https://ifconfig.me 2>/dev/null || true)"
  [ -n "$dns_ip" ] || die "o nome $DOMAIN ainda nao resolve. Aponte o registro para este servidor e tente de novo."
  if [ -n "$server_ip" ] && [ "$dns_ip" != "$server_ip" ]; then
    die "$DOMAIN aponta para $dns_ip, mas este servidor e $server_ip. Ajuste o registro e tente de novo (o certificado falharia)."
  fi
fi

# --- 1. Virtual host novo, so para este nome --------------------------------
# Uma linha por porta: "<endereco:porta> <nome> (<arquivo:linha>)" do virtual host
# padrao, que atende os nomes desconhecidos. Com um unico site o Apache nao escreve
# "default server", por isso as duas formas de saida sao tratadas.
default_vhosts() {
  apache2ctl -S 2>&1 | awk '
    /^[^ ]+:[0-9]+ +is a NameVirtualHost/ { port = $1; next }
    /^ +default server / { sub(/^ +default server /, ""); print port, $0; next }
    /^[^ ]+:[0-9]+ +[^ ]+ \(/ { print $1, $2, $3 }
  ' || true
}
default_before="$(default_vhosts)"

a2enmod proxy proxy_http >/dev/null
if [ ! -e "$CONF" ]; then
  echo ">> Criando o virtual host de $DOMAIN..."
  cat > "$CONF" <<EOF
# API de votos (ai-guidelines): repassa para o container, que ouve so em 127.0.0.1.
<VirtualHost *:80>
    ServerName $DOMAIN
    ProxyPass / $API/
    ProxyPassReverse / $API/
    # Sem log de acesso e sem IP no log de erros: a API nao guarda quem vota.
    CustomLog /dev/null common
    ErrorLogFormat "[%{u}t] [%-m:%l] %M"
    ErrorLog \${APACHE_LOG_DIR}/$SITE-error.log
</VirtualHost>
EOF
  a2ensite "$SITE" >/dev/null
  rollback() { a2dissite "$SITE" >/dev/null 2>&1 || true; rm -f "$CONF"; }
  if ! out="$(apache2ctl configtest 2>&1)"; then
    rollback
    die "o Apache recusou a configuracao nova (desfeita, nada recarregado): $out"
  fi
  default_after="$(default_vhosts)"
  while IFS= read -r line; do
    [ -z "$line" ] || grep -qxF -- "$line" <<<"$default_after" || {
      rollback
      die "a configuracao nova mudaria o site padrao do servidor (desfeita, nada recarregado)."
    }
  done <<<"$default_before"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet apache2; then
    systemctl reload apache2
  else
    apache2ctl graceful
  fi
fi

# --- 2. Certificado e HTTPS so para este nome -------------------------------
if [ "${SKIP_CERTBOT:-0}" != 1 ]; then
  echo ">> Pedindo o certificado (certbot)..."
  certbot_args=(--apache -d "$DOMAIN" --non-interactive --agree-tos --redirect)
  [ -z "$EMAIL" ] || certbot_args+=(-m "$EMAIL")
  certbot "${certbot_args[@]}" \
    || die "o certbot falhou (veja a mensagem acima). O virtual host HTTP de $DOMAIN ficou criado; os outros sites nao foram afetados."
  if ! grep -q ':443 ' <<<"$default_before" && default_vhosts | grep -q ':443 '; then
    echo "AVISO: este servidor nao tinha nenhum site HTTPS; $DOMAIN passou a ser o padrao da porta 443."
  fi
fi

# --- 3. Teste e resumo (para colar de volta) --------------------------------
# --resolve: fala com este mesmo Apache pelo nome, sem depender do DNS nem de
# o servidor conseguir acessar o proprio IP publico.
scheme="https"; port=443
[ "${SKIP_CERTBOT:-0}" != 1 ] || { scheme="http"; port=80; }
health="falhou"
for _ in 1 2 3 4 5; do
  if curl -fsS -m 10 --resolve "$DOMAIN:$port:127.0.0.1" "$scheme://$DOMAIN/api/health" 2>/dev/null | grep -q '"ok":true'; then
    health="ok"
    break
  fi
  sleep 3
done

echo
echo "=========== COLE ESTE RESUMO DE VOLTA ==========="
echo "Dominio:        $DOMAIN"
echo "Teste $scheme:    $health  ($scheme://$DOMAIN/api/health)"
echo "Site padrao:    $(default_vhosts | tr '\n' ';')"
echo "Sites ativos:   $(find /etc/apache2/sites-enabled -mindepth 1 -printf '%f ')"
echo "================================================="
[ "$health" = ok ] || exit 1
