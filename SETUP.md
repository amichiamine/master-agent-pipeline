# SETUP.md — mise en route

Compte environ 45 minutes. Chaque étape est vérifiable avant de passer à la suivante.

---

## 0. Pré-requis

| Outil | Vérification | Note |
|---|---|---|
| `git` | `git --version` | |
| `node` ≥ 18 | `node --version` | pour l'exécuteur HTTP (zéro dépendance) |
| `agy` | `agy --version` | Antigravity CLI, depuis `antigravity.google` |
| `gh` | `gh auth status` | optionnel, pour l'ouverture automatique des PR |
| `script` | `script --version` | fourni par util-linux (déjà présent sur Linux/macOS) |
| `python3` | `python3 --version` | utilisé par `run-pass.sh` pour produire du JSON sûr |

Authentifie `agy` **une fois**, en interactif, avec ton compte Google AI Pro :

```bash
agy            # puis suis le flux de connexion, quitte la session
agy -p "réponds exactement PONG"   # doit afficher PONG
```

> Si cette seconde commande renvoie du vide, tu viens de rencontrer le bug non-TTY.
> C'est normal : `run-pass.sh` le contourne. Teste alors :
> `script -qec 'agy -p "réponds exactement PONG"' /dev/null`

---

## 0 bis. Windows : l'exécuteur doit tourner dans WSL2

Sur Windows 11 / PowerShell 7, `agy -p` ne perd pas seulement son stdout : le mode print **échoue
aussi à réutiliser la session authentifiée** et part en timeout OAuth. La cause documentée est
qu'`agy` invoque en interne PowerShell 5.1, dont `Write-Host` contourne le pipeline standard.
Et le contournement pseudo-TTY (`script`) **n'existe ni en PowerShell, ni dans Git Bash**.

| Environnement | `script` | Verdict |
|---|---|---|
| PowerShell natif | absent | ❌ stdout perdu, auth en timeout |
| Git Bash / MSYS2 | absent | ❌ |
| **WSL2 (Ubuntu)** | fourni par util-linux | ✅ **recommandé** |
| devcontainer (Docker Desktop) | oui | valable, mais s'appuie déjà sur WSL2 |

```powershell
# Windows, une seule fois
wsl --install -d Ubuntu-24.04
wsl --set-default-version 2
```

```bash
# dans Ubuntu — travaille dans ~, JAMAIS depuis /mnt/c (lent, métadonnées git fragiles)
sudo apt update && sudo apt install -y util-linux git curl nodejs npm python3 jq
cd ~ && git clone <ton-depot> && cd <ton-depot>
agy                                                        # authentifie une fois
script -qec 'agy -p "réponds exactement PONG"' /dev/null    # doit afficher PONG
```

Antigravity reste ton IDE côté Windows et sait ouvrir un dossier WSL : tu ne perds rien en confort
d'édition, et l'exécuteur automatisé tourne côté Linux avec un pseudo-TTY qui fonctionne.

### Poser le kit depuis PowerShell

```powershell
tar -xzf master-agent-pipeline-kit.tar.gz
robocopy .\kit .\mon-projet /E    # robocopy, pas Copy-Item : embarque les dossiers cachés
cd .\mon-projet
git add -A; git commit -m "feat: pipeline Master Agent"; git push
```

`robocopy` sort en code non nul même en cas de succès (`1` = fichiers copiés) : c'est normal.

---

## 1. Poser le kit dans ton dépôt

```bash
# depuis la racine de ton projet (ou d'un dépôt neuf)
cp -r kit/. .
git add -A && git commit -m "chore: pipeline master agent"
```

---

## 2. Configurer l'exécuteur

```bash
cd tools/executor
cp .env.example .env
# jeton solide, 48 caractères :
openssl rand -hex 24
```

Renseigne dans `.env` : `EXECUTOR_TOKEN`, `REPO_ROOT` (chemin absolu), `BASE_BRANCH`.

Lance-le :

```bash
set -a && . ./.env && set +a
node server.js
```

Vérifie :

```bash
curl -s localhost:7788/health | jq
curl -s localhost:7788/status -H "Authorization: Bearer $EXECUTOR_TOKEN" | jq
```

---

## 3. Ouvrir le tunnel

C'est ce qui me permet de piloter l'exécuteur directement.

```bash
# éphémère, pour commencer — URL affichée dans la sortie
cloudflared tunnel --url http://127.0.0.1:7788
```

Pour une URL stable (recommandé une fois validé) : `cloudflared tunnel create master-agent`,
puis un enregistrement DNS sur ton domaine.

> ⚠️ **Sécurité.** Cette URL est publique. Le jeton est ta seule barrière — traite-le
> comme un mot de passe et ne le colle jamais dans une conversation ni dans un commit.
> Le serveur n'exécute que des commandes en liste blanche : aucune chaîne que je fournis
> n'atteint un shell. N'ajoute jamais de route « exécute cette commande arbitraire ».
> Coupe le tunnel quand tu ne travailles pas.

---

## 4. Câbler GitHub

1. Protège `main` : PR obligatoire, `verify` requis, pas de push direct.
2. Crée les labels : `pass:go`, `pass:blocked`, `pass:review`, `pass:hold`, `debt`.
3. Optionnel : secret `MASTER_WEBHOOK_URL` pour que le CI me réveille sur PR verte.
4. Garde-fous locaux : `npx lefthook install`.

---

## 5. Remplir le contrat

Deux fichiers à compléter **avant** la première passe — c'est ce qui différencie un
pipeline qui tient d'un pipeline qui dérive :

- **`AGENTS.md` §5** : remplace les commandes de vérification par celles de ta stack réelle.
- **`.agent/ARCHITECTURE.md`** : intention, couches, frontières, et pour chaque règle
  l'outil qui la fait respecter.

Si tu me donnes accès au dépôt, je les écris moi-même à partir d'un audit du code existant.

---

## 6. Première passe

```bash
curl -X POST http://127.0.0.1:7788/pass \
  -H "Authorization: Bearer $EXECUTOR_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"id":"PASS-001","spec":"<contenu de .agent/passes/PASS-001.md>"}'
```

Puis suis l'avancement :

```bash
curl -s localhost:7788/status -H "Authorization: Bearer $EXECUTOR_TOKEN" | jq
```

À la fin : branche `pass/PASS-001` poussée, PR ouverte, rapport dans `.agent/runs/`.
Tu me dis « PASS-001 poussée » (ou le webhook le fait), je juge, et j'enchaîne.

---

## 7. Vers le distant, plus tard

Le montage est déjà prêt pour ça. Trois chemins, sans rien réécrire :

| Cible | Ce qui change |
|---|---|
| **Codespaces** | le devcontainer est déjà là ; lance l'exécuteur dedans et publie le port 7788 en public |
| **VM cloud** | même exécuteur, même tunnel ; auth `agy` via une redirection de port SSH la première fois |
| **CI** | possible seulement avec une clé API Gemini ou une licence Code Assist Standard/Enterprise — pas avec AI Pro |

Seule l'URL de l'exécuteur change. Le contrat, les specs et les juges sont identiques.

---

## Dépannage

| Symptôme | Cause probable | Remède |
|---|---|---|
| sortie vide, code 0 | bug non-TTY d'`agy` | déjà contourné ; vérifie que `script` est installé |
| « auth timed out » dans les logs | session `agy` non authentifiée pour ce contexte | relance `agy` en interactif une fois |
| passe échouée « marqueur absent » | l'exécuteur n'a pas suivi AGENTS.md §7 | rappelle le marqueur dans la spec ; réduis le périmètre |
| `worktree add` échoue | branche déjà existante | `git worktree prune` puis relance |
| CI rouge sur `pass-contract` | rapport de run absent ou incomplet | c'est le garde-fou qui fonctionne : fais compléter le rapport |
