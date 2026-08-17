# PROTOCOL.md — Le protocole de passes

Ce document définit qui fait quoi, dans quel ordre, et par quel canal.
Il est la référence commune au Master Agent (conception), à l'exécuteur (`agy`) et à toi (arbitrage).

---

## Les trois rôles

| Rôle | Qui | Responsabilité | Ne fait jamais |
|---|---|---|---|
| **Master Agent** | Claude (Hyperagent) | scanner, auditer, diagnostiquer, architecturer, planifier, écrire les specs, juger les résultats, recadrer | écrire du code de production |
| **Exécuteur** | `agy` (Antigravity CLI), local | implémenter la spec à la lettre, vérifier, rapporter | décider, élargir le périmètre, improviser |
| **Arbitre** | toi | trancher les questions produit, valider les fusions, définir les priorités | servir de copiste entre les deux |

---

## Le cycle d'une passe

```
1. AUDIT      Master lit le repo (API GitHub + digest repomix) → rapport dans .agent/reports/
2. PLAN       Master découpe en passes → .agent/BACKLOG.md + issues GitHub
3. SPEC       Master écrit .agent/passes/PASS-NNN.md (périmètre, tâches, DoD, budget)
4. DÉCLENCHE  toi : label `pass:go` sur l'issue, ou POST /pass sur l'exécuteur
5. EXÉCUTE    agy travaille sur la branche pass/NNN dans un worktree isolé
6. RAPPORTE   agy écrit .agent/runs/PASS-NNN.run.md + marqueur PASS-DONE / PASS-BLOCKED
7. VÉRIFIE    CI : tests, lint, secrets, règles d'architecture, présence du rapport
8. JUGE       Master lit diff + rapport + CI → verdict
9. VERDICT    ✅ merge | ⚠️ merge + dette inscrite | ❌ PASS-NNNb correctrice
10. MÉMOIRE   Master met à jour STATE.md, BACKLOG.md, et un ADR si une décision a été prise
```

Une passe ne saute jamais l'étape 6 ni l'étape 7. Un résultat non vérifié n'est pas un résultat.

---

## Les états d'une passe

| État | Signification | Où on le voit |
|---|---|---|
| `planned` | spec écrite, pas lancée | BACKLOG.md, issue ouverte |
| `running` | exécuteur au travail | `GET /status`, branche poussée |
| `blocked` | l'exécuteur s'est arrêté et a posé une question | `PASS-BLOCKED`, label `pass:blocked` |
| `to-judge` | PR ouverte, CI terminée | label `pass:review` |
| `rejected` | verdict négatif, passe correctrice émise | commentaire de PR du Master |
| `done` | fusionnée dans `main` | PR fermée, STATE.md à jour |

---

## Les labels comme boutons

| Label | Effet |
|---|---|
| `pass:go` | autorise l'exécution de la passe décrite par l'issue |
| `pass:blocked` | l'exécuteur attend un arbitrage humain |
| `pass:review` | prêt pour le verdict du Master |
| `pass:hold` | gelée, ne pas exécuter |
| `debt` | dette assumée, à replanifier |

---

## Économie de quota — les règles qui comptent

1. **Aucun code collé dans la conversation.** Des références (`src/auth/x.ts:40-90`) suffisent :
   le Master va chercher le contenu lui-même par l'API.
2. **Les logs vivent dans le repo**, dans `.agent/runs/`. Jamais dans le chat.
3. **Le CI filtre avant le Master.** CI rouge → l'exécuteur corrige seul, le Master n'est pas convoqué.
4. **Passes larges, peu nombreuses.** Un aller-retour avec le Master doit valoir plusieurs heures
   d'exécution. Une passe triviale ne remonte pas.
5. **Un digest, pas un dump.** `tools/digest.sh` condense le repo avant tout audit large.
6. **Le Master ne se réveille que sur événement utile** : PR verte, blocage, ou tick planifié —
   jamais sur un commit intermédiaire.

---

## Ce que le Master juge, et ce qu'il ne juge pas

| Il juge | Il ne juge pas (le CI le fait) |
|---|---|
| la conception et les compromis | le formatage |
| le respect des frontières d'architecture | les règles de lint |
| la pertinence des abstractions | la présence de secrets |
| la couverture *utile* des tests | le pourcentage de couverture |
| la dette introduite et son coût futur | le code mort |
| la cohérence avec les décisions passées (ADR) | les types manquants |

Tout ce que la colonne de droite peut attraper ne doit jamais consommer de quota Master.
Si quelque chose y échappe de façon répétée, la bonne réponse est **une nouvelle règle de CI**,
pas une relecture humaine de plus.
