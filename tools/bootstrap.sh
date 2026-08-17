#!/usr/bin/env bash
# bootstrap.sh — initialise un nouveau projet à partir du gabarit.
#
# À lancer UNE FOIS, juste après avoir créé le dépôt depuis le template
# ("Use this template" sur GitHub, ou `gh repo create --template`).
#
#   bash tools/bootstrap.sh "Nom du projet" "description courte"
#
# Ce script est idempotent : le relancer ne casse rien.
set -euo pipefail

NAME="${1:-}"
DESC="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [ -z "$NAME" ]; then
  read -rp "Nom du projet : " NAME
fi
[ -z "$DESC" ] && read -rp "Description en une phrase : " DESC

say() { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[0;33m!\033[0m %s\n' "$*"; }

# ------------------------------------------------------- 1. identité du projet
say "Identité du projet"
if grep -q '^# Pipeline Master Agent' README.md 2>/dev/null; then
  mv README.md docs/KIT-README.md
  cat > README.md <<EOF
# ${NAME}

${DESC}

---

Ce dépôt est piloté par le protocole **Master Agent ⇄ Antigravity**.

- Contrat d'exécution : [\`AGENTS.md\`](AGENTS.md)
- Protocole de passes : [\`.agent/PROTOCOL.md\`](.agent/PROTOCOL.md)
- Architecture cible : [\`.agent/ARCHITECTURE.md\`](.agent/ARCHITECTURE.md)
- État courant : [\`.agent/STATE.md\`](.agent/STATE.md)
- Mode d'emploi du pipeline : [\`docs/guide.html\`](docs/guide.html)

## Démarrage

\`\`\`bash
cd tools/executor && cp .env.example .env   # renseigne EXECUTOR_TOKEN et REPO_ROOT
node server.js
\`\`\`

Puis ouvre \`docs/guide.html\` dans un navigateur pour la suite.
EOF
  ok "README.md remplacé par celui du projet (l'original est dans docs/KIT-README.md)"
else
  warn "README.md déjà personnalisé — inchangé"
fi

# ------------------------------------------------------- 2. état vierge
say "Remise à zéro de l'état de projet"
cat > .agent/STATE.md <<EOF
# STATE.md — état courant

> Mis à jour par le **Master Agent** après chaque passe fusionnée.

## Où on en est

Projet initialisé le $(date -u +%Y-%m-%d) depuis le gabarit. Aucune passe exécutée.
Architecture non encore définie : première tâche du Master.

## Dette assumée

| ID | Description | Introduite par | Coût si non traitée | Passe de nettoyage |
|---|---|---|---|---|

## Zones sensibles

_aucune pour l'instant_

## Questions ouvertes en attente d'arbitrage

- Périmètre fonctionnel de la v1 ?
- Stack technique imposée ou libre ?

## Journal des passes

| Passe | Objectif | Verdict | Date |
|---|---|---|---|
EOF
ok ".agent/STATE.md remis à zéro"

rm -f .agent/passes/PASS-0*.md 2>/dev/null || true
rm -f .agent/runs/PASS-*.run.md 2>/dev/null || true
rm -f .agent/reports/*.md 2>/dev/null || true
rm -rf tools/executor/logs .worktrees 2>/dev/null || true
ok "passes, runs et rapports du projet précédent purgés (les gabarits sont conservés)"

# ------------------------------------------------------- 3. lien vers le gabarit
say "Lien de mise à jour vers le gabarit"
TEMPLATE_URL="${KIT_REMOTE:-https://github.com/amichiamine/master-agent-pipeline.git}"
if git remote get-url kit >/dev/null 2>&1; then
  warn "remote 'kit' déjà présent : $(git remote get-url kit)"
else
  git remote add kit "$TEMPLATE_URL"
  ok "remote 'kit' ajouté → $TEMPLATE_URL"
  echo "    (mises à jour futures : bash tools/kit-update.sh)"
fi

# ------------------------------------------------------- 4. labels GitHub
say "Labels de passe"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh label create "pass:go"      --color 0e8a16 --description "Autorise l'exécution"  2>/dev/null && ok "pass:go"      || warn "pass:go déjà présent"
  gh label create "pass:blocked" --color d93f0b --description "Attend un arbitrage"    2>/dev/null && ok "pass:blocked" || warn "pass:blocked déjà présent"
  gh label create "pass:review"  --color 1d76db --description "Prêt pour le verdict"   2>/dev/null && ok "pass:review"  || warn "pass:review déjà présent"
  gh label create "pass:hold"    --color 5319e7 --description "Gelée"                  2>/dev/null && ok "pass:hold"    || warn "pass:hold déjà présent"
  gh label create "debt"         --color fbca04 --description "Dette assumée"          2>/dev/null && ok "debt"         || warn "debt déjà présent"
else
  warn "gh indisponible — crée les labels à la main : pass:go, pass:blocked, pass:review, pass:hold, debt"
fi

# ------------------------------------------------------- 5. contrôles
say "Contrôles"
command -v agy     >/dev/null && ok "agy présent : $(agy --version 2>/dev/null | head -1)" || warn "agy introuvable — installe Antigravity CLI"
command -v node    >/dev/null && ok "node $(node --version)"                                || warn "node introuvable"
command -v script  >/dev/null && ok "script présent (pseudo-TTY disponible)"                || warn "script introuvable — INDISPENSABLE, installe util-linux"
command -v python3 >/dev/null && ok "python3 présent"                                       || warn "python3 introuvable"
[ -f tools/executor/.env ] && ok ".env présent" || warn ".env absent : cp tools/executor/.env.example tools/executor/.env"

cat <<EOF

──────────────────────────────────────────────────────────────
  ${NAME} est initialisé.

  Il reste DEUX choses, et ce sont les seules qui comptent :

  1. AGENTS.md §5 — fige les commandes de vérification de ta stack
  2. .agent/ARCHITECTURE.md — l'intention, les couches, et pour
     chaque règle l'outil qui la fait respecter

  Un pipeline sans ces deux fichiers remplis dérive. Avec eux, il tient.
  Le Master Agent peut les écrire pour toi à partir d'un audit du code.

  Ensuite : commit, push, et demande la première passe.
──────────────────────────────────────────────────────────────
EOF
