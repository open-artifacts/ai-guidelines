#!/usr/bin/env bash
# Baixa uma copia dos backups da API (SQLite) da VPS para esta maquina.
# Uso:   bash deploy/baixar-backup.sh <host-ssh> [pasta-destino]
#   <host-ssh>       como voce entra por SSH (ex.: deploy@IP, ou um apelido do ~/.ssh/config)
#   [pasta-destino]  onde guardar as copias (padrao: ./backups-vps)
# Opcionais (variaveis de ambiente): SSH (programa ssh) e REMOTE_DIR (pasta do
# projeto na VPS, padrao ai-guidelines).
#
# A API gera um backup consistente por dia (e ao iniciar) em /data/backups, dentro
# do volume do Docker, e guarda os 14 mais recentes. Este script copia cada um para
# fora da VPS, confere o cabecalho SQLite e so entao grava no destino: nomes iguais
# sao sobrescritos, os demais ficam. Nada e alterado na VPS.
#
# Seguranca: a VPS pode ser de terceiros, entao nada vindo dela e interpretado aqui.
# So sao aceitos nomes no formato votes-AAAA-MM-DD.db, copiados um a um (nada de
# desempacotar arquivos enviados pelo servidor).
set -euo pipefail

die() { echo "ERRO: $*" >&2; exit 1; }

HOST="${1:-}"
[ -n "$HOST" ] || die "uso: bash deploy/baixar-backup.sh <host-ssh> [pasta-destino]"
[[ "$HOST" != -* ]] || die "o host nao pode comecar com hifen."
DEST="${2:-backups-vps}"
SSH="${SSH:-ssh}"
REMOTE_DIR="${REMOTE_DIR:-ai-guidelines}"

mkdir -p "$DEST"
tmp="$DEST/.baixando.$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

# Roda um comando na pasta do projeto, na VPS.
remote() { "$SSH" -o BatchMode=yes -- "$HOST" "cd '$REMOTE_DIR' && $1" </dev/null; }

echo ">> Listando os backups em $HOST..."
names="$(remote 'docker compose exec -T api ls -1 /data/backups' \
  | grep -E '^votes-[0-9]{4}-[0-9]{2}-[0-9]{2}\.db$' || true)"
[ -n "$names" ] || die "nenhum backup encontrado na VPS."

count=0
for name in $names; do
  remote "docker compose exec -T api cat /data/backups/$name" > "$tmp/$name"
  [ "$(head -c 15 "$tmp/$name")" = "SQLite format 3" ] \
    || die "$name nao parece um banco SQLite. Nada foi gravado em $DEST."
  count=$((count + 1))
done

mv -f "$tmp"/votes-*.db "$DEST"/
echo ">> $count arquivo(s) em $DEST:"
for name in $names; do
  echo "   $name  ($(wc -c < "$DEST/$name") bytes)"
done
