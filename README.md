# Pipeline Master Agent ⇄ Antigravity

Un dépôt outillé pour séparer **la conception** de **l'exécution** :

- **Master Agent** (Claude, via Hyperagent) — scanne, audite, diagnostique, architecture,
  planifie, écrit les specs, juge les résultats, recadre. Il n'écrit pas de code de production.
- **Exécuteur** (`agy`, Antigravity CLI, en local sur ton abonnement Google AI Pro) —
  implémente les specs à la lettre, vérifie, rapporte. Il ne décide pas.
- **Toi** — tu arbitres et tu fusionnes. Tu n'es plus la courroie de transmission.

Le dépôt est le bus de communication : tout passe par des fichiers versionnés.

---

## Anatomie

```
AGENTS.md                    contrat d'exécution, lu par agy ET par l'IDE Antigravity
.agent/
  PROTOCOL.md                qui fait quoi, dans quel ordre — la référence commune
  ARCHITECTURE.md            structure cible et frontières (Master seulement)
  STATE.md                   état courant, dette, questions ouvertes
  BACKLOG.md                 passes planifiées et ordonnées
  passes/PASS-*.md           specs d'exécution (lecture seule pour l'exécuteur)
  runs/PASS-*.run.md         rapports d'exécution (écrits par agy)
  reports/                   audits et bilans du Master
  decisions/ADR-*.md         décisions d'architecture et leur mode d'application
docs/
  guide.html                 mode d'emploi interactif : installation, déploiement, usages
tools/
  executor/server.js         serveur HTTP local : le Master pilote l'exécuteur
  executor/run-pass.sh       lance agy de façon fiable (worktree, PTY, validation)
  digest.sh                  condense le dépôt pour les audits — économise du quota
.github/
  workflows/verify.yml       les juges : contrat de passe, secrets, qualité, architecture
  workflows/wake-master.yml  réveille le Master sur les événements qui comptent
  ISSUE_TEMPLATE/pass.yml    gabarit d'issue-passe
.devcontainer/               un environnement unique pour local, Codespaces et CI
```

---

## Le cycle

```
AUDIT ─► PLAN ─► SPEC ─► [label pass:go] ─► agy exécute ─► rapport + PR
                                                              │
   verdict ◄─── Master lit diff + rapport + CI ◄─── CI (juges) ┘
      │
      ├─ ✅ merge, STATE.md à jour, passe suivante
      ├─ ⚠️ merge + dette inscrite au backlog
      └─ ❌ passe correctrice PASS-XXXb
```

Détail complet dans [`.agent/PROTOCOL.md`](.agent/PROTOCOL.md).

---

## Les trois garanties du montage

**1. L'exécuteur ne peut pas dériver silencieusement.**
Périmètre déclaré, fichiers de contrat protégés par le CI, rapport de run obligatoire et
vérifié, marqueur de fin explicite. Le CI refuse une passe sans rapport conforme, même si
le code est correct.

**2. L'architecture est opposable, pas décorative.**
Toute règle de `ARCHITECTURE.md` doit avoir une contrepartie exécutable (dependency-cruiser,
lint, typage strict, seuils). Une règle qu'aucun outil ne vérifie est une intention.
C'est ce qui permet au Master de ne plus relire ce qu'une machine peut attraper.

**3. Le quota du Master est protégé par construction.**
Le CI filtre en amont : rouge → l'exécuteur corrige seul, le Master n'est pas convoqué.
Les logs vivent dans le repo, jamais dans la conversation. Les audits passent par un digest
condensé. Le Master ne se réveille que sur PR verte, blocage, ou tick planifié.

---

## Points techniques à connaître (vérifiés, août 2026)

| Fait | Conséquence câblée dans le kit |
|---|---|
| Gemini CLI ne sert plus les tiers AI Pro/Ultra depuis le 18 juin 2026 | l'exécuteur est **`agy`** (Antigravity CLI), pas `gemini` |
| `GEMINI.md` est remplacé par **`AGENTS.md`** | un seul contrat pour `agy` et pour l'IDE |
| `agy -p` **perd son stdout en non-TTY** et sort quand même en code 0 | `run-pass.sh` l'enveloppe dans un pseudo-TTY (`script -qec`) |
| le code de sortie n'est pas fiable | le statut vient du **marqueur** `PASS-DONE` / `PASS-BLOCKED`, jamais du code |
| `--output-format json` n'est pas stable | on parse du texte avec marqueurs, pas du JSON |
| timeout par défaut de `-p` : 5 min | `--print-timeout` explicite + plafond dur `timeout` |
| quota Pro désormais hebdomadaire par compute | passes larges et peu nombreuses ; budget déclaré par passe |

---

## Ce dépôt est un **gabarit**

Il n'est pas destiné à être cloné puis renommé. Marque-le comme
**Template repository** (Settings → General → Template repository), puis pour chaque projet :

```bash
gh repo create mon-nouveau-projet \
  --template amichiamine/master-agent-pipeline --private --clone
cd mon-nouveau-projet
bash tools/bootstrap.sh "Mon nouveau projet" "ce que fait le projet"
```

Le nouveau dépôt naît avec un **historique vierge** et son propre `origin` — aucun risque de
pousser dans le gabarit par erreur. `bootstrap.sh` remet l'état à zéro, purge les passes de
l'exemple, ajoute le gabarit comme remote `kit`, crée les labels et vérifie l'outillage.

Quand tu améliores le gabarit, propage la mise à jour dans un projet existant :

```bash
bash tools/kit-update.sh           # aperçu des différences
bash tools/kit-update.sh --apply   # branche chore/kit-update-AAAAMMJJ
```

Seuls les chemins du gabarit sont écrasés. `ARCHITECTURE.md`, `STATE.md`, `BACKLOG.md`,
les passes, les rapports, le `README.md` du projet et tout le code métier restent intacts.

---

## Démarrage

Ouvre **[`docs/guide.html`](docs/guide.html)** dans un navigateur : configurateur qui adapte
toutes les commandes à tes chemins, checklist d'installation persistante, générateur de specs
de passe, et dépannage. Version texte équivalente dans [`SETUP.md`](SETUP.md). En résumé : installer `agy`, générer un jeton, lancer
l'exécuteur, ouvrir un tunnel, remplir `ARCHITECTURE.md`, lancer PASS-001.
