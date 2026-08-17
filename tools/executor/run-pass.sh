#!/usr/bin/env bash
# run-pass.sh — exécute une passe avec Antigravity CLI (agy) de façon fiable.
#
# Usage : run-pass.sh <PASS_ID> <SPEC_FILE> [BASE_BRANCH]
#
# Contourne trois pièges connus de `agy -p` :
#   1. en non-TTY, le stdout est silencieusement perdu  -> pseudo-TTY via `script`
#   2. le code de sortie est 0 même sans sortie          -> validation par marqueur
#   3. timeout par défaut de 5 min                       -> --print-timeout explicite
#
set -uo pipefail

PASS_ID="${1:?usage: run-pass.sh <PASS_ID> <SPEC_FILE> [BASE_BRANCH]}"
SPEC_FILE="${2:?spec file manquant}"
BASE_BRANCH="${3:-${BASE_BRANCH:-main}}"

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
AGENT_CMD="${AGENT_CMD:-agy}"
AGENT_MODEL="${AGENT_MODEL:-}"
PRINT_TIMEOUT="${PRINT_TIMEOUT:-30m}"
HARD_TIMEOUT="${HARD_TIMEOUT:-2400}"          # secondes, filet de sécurité
WORKTREES_DIR="${WORKTREES_DIR:-$REPO_ROOT/.worktrees}"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/tools/executor/logs}"
AUTO_PUSH="${AUTO_PUSH:-1}"
OPEN_PR="${OPEN_PR:-1}"
SKIP_PERMISSIONS="${SKIP_PERMISSIONS:-1}"     # worktree dédié = espace contrôlé

BRANCH="pass/${PASS_ID}"
WT="${WORKTREES_DIR}/${PASS_ID}"
RAW_LOG="${LOG_DIR}/${PASS_ID}.raw.log"
CLEAN_LOG="${LOG_DIR}/${PASS_ID}.log"
PROMPT_FILE="${LOG_DIR}/${PASS_ID}.prompt.txt"
INNER="${LOG_DIR}/${PASS_ID}.inner.sh"

mkdir -p "$LOG_DIR" "$WORKTREES_DIR"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
emit() { printf '%s\n' "$1"; }   # JSON sur stdout, consommé par server.js

fail() {
  emit "$(printf '{"pass":"%s","status":"failed","reason":%s,"log":"%s"}' \
    "$PASS_ID" "$(json_str "$1")" "$CLEAN_LOG")"
  exit 1
}

json_str() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }

# ---------------------------------------------------------------- pré-requis
command -v git >/dev/null || fail "git introuvable"
command -v "$AGENT_CMD" >/dev/null || fail "$AGENT_CMD introuvable dans le PATH"
[ -f "$SPEC_FILE" ] || fail "spec introuvable : $SPEC_FILE"

# ---------------------------------------------------------------- worktree isolé
cd "$REPO_ROOT"
log "préparation du worktree $WT"
git fetch --quiet origin "$BASE_BRANCH" 2>/dev/null || log "fetch ignoré (pas de remote ?)"

if git worktree list --porcelain | grep -qx "worktree $WT"; then
  log "worktree existant réutilisé"
else
  if git show-ref --quiet "refs/heads/$BRANCH"; then
    git worktree add "$WT" "$BRANCH" >/dev/null 2>&1 || fail "worktree add a échoué"
  else
    git worktree add -b "$BRANCH" "$WT" "origin/$BASE_BRANCH" >/dev/null 2>&1 \
      || git worktree add -b "$BRANCH" "$WT" "$BASE_BRANCH" >/dev/null 2>&1 \
      || fail "impossible de créer la branche $BRANCH"
  fi
fi

# La spec doit être lisible depuis le worktree.
mkdir -p "$WT/.agent/passes" "$WT/.agent/runs"
cp "$SPEC_FILE" "$WT/.agent/passes/$(basename "$SPEC_FILE")" 2>/dev/null || true

# ---------------------------------------------------------------- prompt
cat > "$PROMPT_FILE" <<PROMPT
Tu exécutes la passe ${PASS_ID} sur ce dépôt.

Respecte AGENTS.md à la lettre : il est le contrat non négociable de cette exécution.
Lis d'abord .agent/ARCHITECTURE.md puis .agent/STATE.md.

Tu travailles sur la branche ${BRANCH}. Ne change pas de branche.

Rappels critiques :
- reste strictement dans le PÉRIMÈTRE AUTORISÉ de la spec ; hors périmètre, lecture seule ;
- si la spec est ambiguë, ne devine pas : consigne la question et arrête-toi ;
- écris .agent/runs/${PASS_ID}.run.md avec toutes les sections exigées par AGENTS.md §6 ;
- termine ta sortie par exactement une ligne :
    PASS-DONE: ${PASS_ID} — <résumé en une ligne>
  ou
    PASS-BLOCKED: ${PASS_ID} — <raison en une ligne>

=================== SPEC DE LA PASSE ===================
$(cat "$SPEC_FILE")
========================================================
PROMPT

# ---------------------------------------------------------------- invocation
AGY_ARGS=(-p --print-timeout "$PRINT_TIMEOUT")
[ -n "$AGENT_MODEL" ] && AGY_ARGS+=(--model "$AGENT_MODEL")
[ "$SKIP_PERMISSIONS" = "1" ] && AGY_ARGS+=(--dangerously-skip-permissions)

# Les arguments sont échappés un par un : un nom de modèle contient des espaces
# (ex. "Gemini 3.1 Pro (High)") et casserait une expansion naïve.
AGY_ARGS_STR="$(printf '%q ' "${AGY_ARGS[@]}")"

cat > "$INNER" <<INNER_EOF
#!/usr/bin/env bash
cd $(printf '%q' "$WT") || exit 90
exec $(printf '%q' "$AGENT_CMD") ${AGY_ARGS_STR} "\$(cat $(printf '%q' "$PROMPT_FILE"))"
INNER_EOF
chmod +x "$INNER"

run_once() {
  : > "$RAW_LOG"
  if [ "$(uname -s)" = "Darwin" ]; then
    timeout "$HARD_TIMEOUT" script -q /dev/null "$INNER" >"$RAW_LOG" 2>&1
  else
    timeout "$HARD_TIMEOUT" script -qec "$INNER" /dev/null >"$RAW_LOG" 2>&1
  fi
  local rc=$?
  # nettoyage des séquences ANSI et des CR laissés par le pseudo-TTY
  sed -r 's/\x1B\[[0-9;?]*[A-Za-z]//g' "$RAW_LOG" | tr -d '\r' > "$CLEAN_LOG"
  return $rc
}

log "exécution de $AGENT_CMD (timeout $PRINT_TIMEOUT, plafond ${HARD_TIMEOUT}s)"
run_once; RC=$?

# Piège n°2 : sortie vide malgré rc=0 -> une seule relance, puis échec net.
if [ ! -s "$CLEAN_LOG" ] || [ -z "$(tr -d '[:space:]' < "$CLEAN_LOG")" ]; then
  log "sortie vide (bug non-TTY probable) — relance unique"
  sleep 5
  run_once; RC=$?
fi

if [ ! -s "$CLEAN_LOG" ] || [ -z "$(tr -d '[:space:]' < "$CLEAN_LOG")" ]; then
  fail "sortie vide après relance : capture non-TTY ou authentification agy échouée"
fi

# ---------------------------------------------------------------- verdict d'exécution
MARKER="$(grep -Eo '^PASS-(DONE|BLOCKED): .*' "$CLEAN_LOG" | tail -1)"
if [ -z "$MARKER" ]; then
  fail "marqueur PASS-DONE/PASS-BLOCKED absent (rc=$RC) — passe considérée en échec"
fi

STATUS="done"
case "$MARKER" in
  PASS-BLOCKED:*) STATUS="blocked" ;;
esac

# Le rapport de run est obligatoire.
RUN_REPORT="$WT/.agent/runs/${PASS_ID}.run.md"
if [ ! -f "$RUN_REPORT" ]; then
  log "rapport de run absent — création d'un rapport minimal depuis les logs"
  mkdir -p "$(dirname "$RUN_REPORT")"
  {
    echo "# Run ${PASS_ID}"
    echo
    echo "> ⚠️ Rapport non produit par l'exécuteur. Reconstruit automatiquement — à considérer comme incomplet."
    echo
    echo '## Sortie brute'
    echo '```'
    tail -n 400 "$CLEAN_LOG"
    echo '```'
  } > "$RUN_REPORT"
fi

# ---------------------------------------------------------------- commit / push / PR
cd "$WT"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c user.name="${GIT_USER_NAME:-antigravity-executor}" \
      -c user.email="${GIT_USER_EMAIL:-executor@local}" \
      commit -q -m "chore(${PASS_ID}): run report and pending changes" -m "Refs ${PASS_ID}" || true
fi

PR_URL=""
if [ "$AUTO_PUSH" = "1" ]; then
  if git push -q -u origin "$BRANCH" 2>/dev/null; then
    log "branche poussée : $BRANCH"
    if [ "$OPEN_PR" = "1" ] && command -v gh >/dev/null; then
      PR_URL="$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
        --title "${PASS_ID}: $(echo "$MARKER" | sed 's/^PASS-[A-Z]*: //')" \
        --body "Passe automatisée ${PASS_ID}.

Marqueur : \`${MARKER}\`

Rapport de run : \`.agent/runs/${PASS_ID}.run.md\`

_Ouvert par l'exécuteur. Verdict attendu du Master Agent._" \
        --label "pass:review" 2>/dev/null || gh pr view --json url -q .url 2>/dev/null || true)"
      [ -n "$PR_URL" ] && log "PR : $PR_URL"
    fi
  else
    log "push échoué (pas de remote, ou droits insuffisants)"
  fi
fi

CHANGED="$(git diff --name-only "origin/$BASE_BRANCH...$BRANCH" 2>/dev/null | head -100 | paste -sd, - || true)"

emit "$(python3 - "$PASS_ID" "$STATUS" "$MARKER" "$BRANCH" "$PR_URL" "$CLEAN_LOG" "$CHANGED" <<'PY'
import json, sys
k = ["pass","status","marker","branch","pr","log","changed"]
print(json.dumps(dict(zip(k, sys.argv[1:]))))
PY
)"
