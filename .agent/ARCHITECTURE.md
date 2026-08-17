# ARCHITECTURE.md

> Écrit et maintenu par le **Master Agent**. En lecture seule pour l'exécuteur.
> Ce fichier décrit la structure **cible**, pas l'état courant (voir STATE.md).

## Intention du projet

<!-- À remplir : en trois phrases. Le problème, pour qui, et le critère de réussite. -->

## Couches et frontières

<!-- Exemple à adapter :
| Couche | Dossier | Peut dépendre de | Ne dépend jamais de |
|---|---|---|---|
| présentation | src/ui/** | domaine | infrastructure, base |
| domaine | src/domain/** | rien | tout le reste |
| infrastructure | src/infra/** | domaine | présentation |
-->

## Règles opposables

Toute règle listée ici **doit** avoir une contrepartie exécutable en CI.
Une règle qu'aucun outil ne vérifie est une intention, pas une règle.

| Règle | Outil qui la fait respecter |
|---|---|
| <!-- la présentation ne touche pas la base --> | <!-- dependency-cruiser --> |

## Décisions structurantes

Voir `.agent/decisions/`. Toute décision d'architecture donne lieu à un ADR.
On ne rediscute jamais une décision consignée sans un nouvel ADR qui la remplace.
