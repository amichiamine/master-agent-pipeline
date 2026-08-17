#!/usr/bin/env bash
# Condense le dépôt en un digest compact, pour que le Master Agent puisse auditer
# sans lire fichier par fichier. Sortie : .agent/reports/digest.md
set -euo pipefail
ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
OUT="$ROOT/.agent/reports/digest.md"
mkdir -p "$(dirname "$OUT")"

if command -v npx >/dev/null 2>&1; then
  npx --yes repomix --style markdown --output "$OUT" \
      --ignore "**/node_modules/**,**/dist/**,**/build/**,**/.worktrees/**,**/tools/executor/logs/**" \
      "$ROOT" && { echo "digest écrit : $OUT"; exit 0; }
fi

echo "repomix indisponible — digest de repli (arborescence + statistiques)" >&2
{
  echo "# Digest de repli"
  echo
  echo "## Arborescence suivie par git"
  echo '```'
  git -C "$ROOT" ls-files | head -800
  echo '```'
  echo
  echo "## Volume par extension"
  echo '```'
  git -C "$ROOT" ls-files | sed -n 's/.*\.\([a-zA-Z0-9]*\)$/\1/p' | sort | uniq -c | sort -rn | head -30
  echo '```'
  echo
  echo "## 40 derniers commits"
  echo '```'
  git -C "$ROOT" log --oneline -40
  echo '```'
} > "$OUT"
echo "digest écrit : $OUT"
