#!/usr/bin/env bash
# kit-update.sh — récupère les améliorations du gabarit dans un projet existant,
# SANS toucher au code métier ni à l'état du projet.
#
#   bash tools/kit-update.sh            # aperçu des différences
#   bash tools/kit-update.sh --apply    # applique sur une branche dédiée
#
# Principe : on ne fusionne pas les historiques (ils sont indépendants).
# On extrait uniquement les chemins qui appartiennent au gabarit.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
REMOTE="${KIT_REMOTE_NAME:-kit}"
REF="${KIT_REF:-main}"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

# Chemins gouvernés par le gabarit. Tout le reste appartient au projet.
KIT_PATHS=(
  "AGENTS.md"
  ".agent/PROTOCOL.md"
  ".agent/passes/PASS-TEMPLATE.md"
  ".agent/decisions/ADR-TEMPLATE.md"
  ".github/workflows/verify.yml"
  ".github/workflows/wake-master.yml"
  ".github/ISSUE_TEMPLATE/pass.yml"
  ".github/pull_request_template.md"
  ".devcontainer/devcontainer.json"
  "tools/executor/server.js"
  "tools/executor/run-pass.sh"
  "tools/executor/README.md"
  "tools/executor/.env.example"
  "tools/digest.sh"
  "tools/bootstrap.sh"
  "tools/kit-update.sh"
  "lefthook.yml"
  "docs/guide.html"
  "SETUP.md"
)

# JAMAIS écrasés : ils portent l'état et les décisions du projet.
# .agent/ARCHITECTURE.md  .agent/STATE.md  .agent/BACKLOG.md
# .agent/passes/PASS-0*   .agent/runs/*    .agent/reports/*
# README.md  tools/executor/.env  et tout le code métier

git remote get-url "$REMOTE" >/dev/null 2>&1 || {
  echo "remote '$REMOTE' absent. Ajoute-le :"
  echo "  git remote add kit https://github.com/amichiamine/master-agent-pipeline.git"
  exit 1
}

echo "▸ récupération de $REMOTE/$REF"
git fetch --quiet "$REMOTE" "$REF"

echo "▸ différences sur les chemins du gabarit"
CHANGED=0
for p in "${KIT_PATHS[@]}"; do
  if git cat-file -e "$REMOTE/$REF:$p" 2>/dev/null; then
    if ! git diff --quiet "$REMOTE/$REF:$p" -- "$p" 2>/dev/null; then
      SIZE=$(git diff --numstat "$REMOTE/$REF:$p" -- "$p" 2>/dev/null | awk '{print "+"$1" -"$2}')
      printf '  \033[0;33m~\033[0m %-46s %s\n' "$p" "${SIZE:-nouveau}"
      CHANGED=$((CHANGED+1))
    fi
  fi
done

[ "$CHANGED" -eq 0 ] && { echo "  ✓ le gabarit est déjà à jour"; exit 0; }

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "$CHANGED fichier(s) à mettre à jour. Pour appliquer :"
  echo "  bash tools/kit-update.sh --apply"
  exit 0
fi

BR="chore/kit-update-$(date -u +%Y%m%d)"
echo "▸ application sur la branche $BR"
git switch -c "$BR" 2>/dev/null || git switch "$BR"

for p in "${KIT_PATHS[@]}"; do
  if git cat-file -e "$REMOTE/$REF:$p" 2>/dev/null; then
    mkdir -p "$(dirname "$p")"
    git show "$REMOTE/$REF:$p" > "$p"
    git add "$p"
  fi
done

chmod +x tools/*.sh tools/executor/*.sh 2>/dev/null || true
git commit -q -m "chore: mise à jour du kit depuis le gabarit" \
  -m "Chemins du gabarit uniquement. Architecture, état, backlog et code métier intacts."

echo "  ✓ commit créé sur $BR"
echo
echo "Relis le diff avant de fusionner — verify.yml et AGENTS.md conditionnent tout le pipeline :"
echo "  git diff main..$BR"
