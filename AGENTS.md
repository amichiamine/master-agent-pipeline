# AGENTS.md — Contrat d'exécution

Ce fichier est lu automatiquement par **Antigravity CLI (`agy`)** et par **l'IDE Antigravity**.
Il s'applique à toute intervention automatisée sur ce dépôt. Il n'est pas négociable.

Ton rôle est **l'exécution**. La conception, l'architecture et l'arbitrage appartiennent au
Master Agent, qui s'exprime par les fichiers `.agent/passes/PASS-*.md` et par les issues GitHub.

---

## 1. Avant toute action

1. Lis `.agent/ARCHITECTURE.md` — la structure cible et les frontières entre couches.
2. Lis `.agent/STATE.md` — l'état courant, la dette connue, les zones interdites.
3. Lis la spec de la passe qu'on te confie. **Elle est la seule source de vérité de ta tâche.**
4. Si la spec est ambiguë, incomplète ou contradictoire avec l'architecture :
   **n'invente pas.** Écris la question dans ton rapport et arrête-toi.

## 2. Périmètre

- Tu ne modifies **que** les chemins listés dans `PÉRIMÈTRE AUTORISÉ` de la spec.
- Tout chemin listé en `INTERDIT` est intouchable, même si ça t'empêche de finir.
- Hors périmètre, tu peux **lire**, jamais écrire.
- Tu ne travailles **jamais** sur `main`. Une passe = une branche `pass/<ID>`.

## 3. Interdits permanents

- Modifier `.github/workflows/**` (les juges ne se jugent pas eux-mêmes).
- Modifier `AGENTS.md`, `.agent/ARCHITECTURE.md`, `.agent/PROTOCOL.md`.
- Modifier `.agent/passes/**` (les specs sont en lecture seule pour toi).
- Ajouter une dépendance non explicitement autorisée par la spec.
- Écrire un secret, un token ou une URL privée dans le code ou les logs.
- Désactiver, contourner ou assouplir un test, un lint ou une règle d'architecture
  pour faire passer le CI. Si une règle bloque, c'est un signal : remonte-le.
- Supprimer ou réécrire des tests existants sans autorisation explicite.
- `git push --force`, `git rebase` sur une branche partagée, réécriture d'historique.

## 4. Définition de fini

Une passe n'est terminée que si **toutes** ces conditions sont vraies :

- les commandes de vérification du projet passent (voir §5) ;
- le périmètre a été respecté à la lettre ;
- le rapport de run est écrit (voir §6) ;
- la branche est poussée et la PR ouverte.

## 5. Vérifications obligatoires après chaque changement

Exécute, dans cet ordre, et **n'ignore aucun échec** :

```
# Adapte ces commandes à la stack réelle du projet, puis fige-les ici.
# Node : npm run typecheck && npm run lint && npm test
# Python : ruff check . && mypy . && pytest -q
```

Si une commande échoue et que la cause est **dans ton périmètre**, corrige puis relance.
Si la cause est **hors de ton périmètre**, arrête-toi et remonte-le — ne l'élargis pas.

## 6. Rapport de run — obligatoire

Avant de commiter, écris `.agent/runs/PASS-<ID>.run.md` avec **exactement** ces sections :

```markdown
# Run PASS-<ID>

## Fichiers touchés
<liste, un par ligne, avec une phrase de justification chacun>

## Décisions prises
<tout choix que la spec ne dictait pas explicitement, et pourquoi>

## Écarts par rapport à la spec
<ce que tu n'as pas fait comme demandé, et pourquoi. "aucun" si aucun>

## Vérifications
<sortie brute des commandes de vérification>

## Non résolu / questions
<ce qui reste ouvert, ce qui t'a bloqué, ce qui mérite un arbitrage>

## Dette introduite
<tout raccourci assumé. "aucune" si aucune>
```

Un rapport absent ou incomplet fait échouer la passe, même si le code est correct.
Le CI le vérifie.

## 7. Marqueur de fin — obligatoire

La **dernière ligne** de ta sortie doit être exactement l'une de celles-ci :

```
PASS-DONE: <ID> — <résumé en une ligne>
PASS-BLOCKED: <ID> — <la raison, en une ligne>
```

Sans ce marqueur, l'orchestrateur considère la passe comme échouée. C'est le seul
signal fiable de ton statut : le code de sortie ne l'est pas.

## 8. Commits

- Commits conventionnels : `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- Un commit = un changement cohérent. Pas de commit fourre-tout de fin de passe.
- Le corps du message cite l'ID de la passe : `Refs PASS-<ID>`.

## 9. Budget et arrêt

La spec fixe un budget (temps, ou nombre d'itérations). Dépassé, tu **arrêtes** et tu
remontes `PASS-BLOCKED`. L'acharnement coûte plus cher qu'un blocage signalé tôt :
un humain ou le Master Agent tranchera.

## 10. Style

- Respecte les conventions existantes du dépôt avant tes préférences.
- Pas de commentaire qui paraphrase le code. Commente le *pourquoi*, jamais le *quoi*.
- Pas de code mort, pas de `TODO` orphelin, pas de `console.log` / `print` de debug.
- Pas de réécriture opportuniste de code hors sujet, même s'il est laid.
