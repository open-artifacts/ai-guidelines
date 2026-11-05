#!/usr/bin/env bash
# Baixa uma copia dos backups da API (SQLite) da VPS para esta maquina.
# Uso:   bash deploy/baixar-backup.sh <host-ssh> [pasta-destino]
#   <host-ssh>       como voce entra por SSH (ex.: deploy@IP, ou um apelido do ~/.ssh/config)
#   [pasta-destino]  onde guardar as copias (padrao: ./backups-vps)
# Opcionais (variaveis de ambiente): SSH (programa ssh) e REMOTE_DIR (pasta do
# projeto na VPS, padrao ai-guidelines).
#
# A API gera um backup consistente por dia (e ao iniciar) em /data/backups, dentro
# do volume do Docker, e guarda os 14 mais recentes. Este script copia todos para
# fora da VPS, confere o cabecalho de cada arquivo e so entao grava no destino:
# nomes iguais sao sobrescritos, os demais ficam. Nada e alterado na VPS.
set -euo pipefail

HOST="${1:-}"
[ -n "$HOST" ] || { echo "Uso: bash deploy/baixar-backup.sh <host-ssh> [pasta-destino]" >&2; exit 1; }
DEST="${2:-backups-vps}"
SSH="${SSH:-ssh}"
REMOTE_DIR="${REMOTE_DIR:-ai-guidelines}"

mkdir -p "$DEST"
tmp="$DEST/.baixando.$$"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

echo ">> Baixando os backups de $HOST..."
"$SSH" -o BatchMode=yes "$HOST" \
  "cd '$REMOTE_DIR' && docker compose exec -T api tar -C /data/backups -cf - ." </dev/null \
  | tar -xf - -C "$tmp"

count=0
for f in "$tmp"/votes-*.db; do
  [ -e "$f" ] || continue
  if [ "$(head -c 15 "$f")" != "SQLite format 3" ]; then
    echo "ERRO: $(basename "$f") nao parece um banco SQLite. Nada foi gravado em $DEST." >&2
    exit 1
  fi
  count=$((count + 1))
done
[ "$count" -gt 0 ] || { echo "ERRO: nenhum backup encontrado na VPS." >&2; exit 1; }

mv -f "$tmp"/votes-*.db "$DEST"/
echo ">> $count arquivo(s) em $DEST:"
for f in "$DEST"/votes-*.db; do
  echo "   $(basename "$f")  ($(wc -c < "$f") bytes)"
done
