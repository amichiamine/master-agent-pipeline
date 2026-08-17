# PASS-XXX — <titre>

> Spec écrite par le Master Agent. Lecture seule pour l'exécuteur.
> Elle est la seule source de vérité de cette passe.

## Objectif

<Une phrase. Le résultat attendu, jamais la méthode.>

## Pourquoi maintenant

<Le lien avec l'architecture, l'audit ou la dette. Ce qui justifie de dépenser une passe ici.>

## Branche

`pass/XXX`, créée depuis `main`.

## PÉRIMÈTRE AUTORISÉ

```
src/<module>/**
tests/<module>/**
```

## INTERDIT

```
.github/workflows/**
AGENTS.md
.agent/ARCHITECTURE.md
<tout autre chemin sensible>
```

## Contexte à lire d'abord

- `.agent/ARCHITECTURE.md` — <la section qui compte ici>
- `.agent/STATE.md` — <la dette concernée>
- `<fichier:lignes>` — <pourquoi il compte>

## Tâches ordonnées

1. <atomique, vérifiable>
2. <atomique, vérifiable>
3. <atomique, vérifiable>

## Définition de fini

- [ ] <critère objectif, vérifiable par une commande>
- [ ] les vérifications d'AGENTS.md §5 passent
- [ ] `.agent/runs/PASS-XXX.run.md` est complet

## Pièges connus

<Ce sur quoi un exécuteur va probablement se tromper. Anticipe-le explicitement.>

## Budget

<durée cible> · <nombre max d'itérations de correction> · au-delà : `PASS-BLOCKED`

## Si ambiguïté

N'invente pas. Consigne la question dans le rapport et arrête-toi.
