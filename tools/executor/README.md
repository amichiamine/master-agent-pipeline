# Exécuteur HTTP

Pont entre le Master Agent et Antigravity CLI (`agy`). Zéro dépendance, Node ≥ 18.

## Routes

| Route | Auth | Rôle |
|---|---|---|
| `GET /health` | non | vivant, dépôt, occupation |
| `GET /status` | oui | job courant, file, historique récent |
| `GET /jobs/:id` | oui | détail d'un job + fin du log |
| `POST /pass` | oui | `{ id, spec, base? }` — lance une passe |
| `POST /command` | oui | `{ name, args? }` — commande en **liste blanche** |

Auth : `Authorization: Bearer $EXECUTOR_TOKEN`.

## Frontière de sécurité

`COMMANDS` dans `server.js` est la liste blanche. Aucune chaîne fournie par l'appelant
n'atteint un shell : le nom est résolu en couple (binaire, arguments) côté serveur, et les
arguments supplémentaires sont filtrés par expression régulière.

**N'ajoute jamais une route qui exécute une commande arbitraire.** Pour une nouvelle
capacité, ajoute une entrée nommée dans `COMMANDS`.

## Ce que fait `run-pass.sh`

1. Crée un `git worktree` isolé sur `pass/<ID>` — l'IDE et l'exécuteur ne se marchent pas dessus.
2. Compose le prompt : rappel du contrat + spec intégrale.
3. Lance `agy -p` **dans un pseudo-TTY** (contourne la perte de stdout en non-TTY).
4. Nettoie les séquences ANSI, relance une fois si la sortie est vide.
5. Valide le **marqueur** `PASS-DONE` / `PASS-BLOCKED` — jamais le code de sortie.
6. Garantit la présence d'un rapport de run (en reconstruit un minimal si besoin, marqué comme incomplet).
7. Commit, push, ouvre la PR avec le label `pass:review`.
8. Émet une ligne JSON de synthèse, consommée par `server.js`.

## Changer d'exécuteur

Le contrat vit dans le dépôt, donc l'exécuteur est remplaçable. Quota hebdomadaire épuisé ?
`AGENT_CMD=qwen` (ou `opencode`, `aider`) dans `.env`. La spec ne change pas.
