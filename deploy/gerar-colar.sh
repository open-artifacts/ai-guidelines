#!/usr/bin/env bash
# Gera um texto para colar no terminal da VPS: ele grava o script em /tmp e o roda
# com sudo. Serve para quem administra o servidor e nao usa git: abre o arquivo,
# copia tudo, cola no terminal e da Enter.
#
# Uso:  bash deploy/gerar-colar.sh <script> [argumento...] > deploy/colar-<nome>.txt
# Ex.:  bash deploy/gerar-colar.sh deploy/bootstrap-vps.sh 'ssh-ed25519 AAAA... x' > deploy/colar-bootstrap.txt
#
# Os arquivos deploy/*.txt ficam fora do git. O script precisa ter so ASCII e
# quebras de linha LF, porque terminais web costumam corromper o resto ao colar.
set -euo pipefail

die() { echo "ERRO: $*" >&2; exit 1; }

script="${1:-}"
[ -f "$script" ] || die "uso: bash deploy/gerar-colar.sh <script> [argumento...] > arquivo.txt"
shift

name="$(basename "$script")"
marker="EOF_COLAR"
[[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "nome de script nao suportado: $name"
LC_ALL=C grep -q '[^[:print:][:space:]]' "$script" && die "$name tem caracteres fora do ASCII."
[ "$(tr -cd '\r' < "$script" | wc -c)" -eq 0 ] || die "$name tem quebras de linha CRLF."
grep -qx "$marker" "$script" && die "$name contem a linha $marker."

quote="'"
escaped="'\\''"
command="sudo bash /tmp/$name"
for arg in "$@"; do
  command+=" '${arg//$quote/$escaped}'"
done

printf "cat > /tmp/%s <<'%s'\n" "$name" "$marker"
cat "$script"
printf '%s\n' "$marker"
printf '%s\n' "$command"
