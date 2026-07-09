# Widget Claude v1.42(x)

Widget de bureau pour Windows 11 qui affiche **en direct ta consommation Claude** : la fenêtre de session (5 h) et le quota hebdomadaire (7 jours), avec le temps restant avant chaque reset.

Les données sont lues via la session **Claude Code** déjà présente sur le PC (API OAuth de consommation). Aucun mot de passe ni jeton n'est stocké par le widget : il réutilise uniquement les identifiants existants de Claude Code.

---

## Aperçu

<p align="center">
  <img src="docs/widget.png" alt="Widget Claude posé sur le bureau, affichant la consommation Session et Semaine" width="340">
</p>

Affichage :

| Mode | Fichier | Description |
|------|---------|-------------|
| **Flottant** | `ClaudeWidget.exe` | Petit panneau posé sur le bureau, déplaçable au clic-glissé (position, taille et thème mémorisés). |

Barres de couleur : 🟢 vert < 50 %, 🟠 ambre 50–85 %, 🔴 rouge > 85 %.
Les données se rafraîchissent automatiquement toutes les 2 minutes.

---

## 🚀 Nouveautés v1.42(x)

- **Journal de diagnostic** : le widget écrit une ligne par relève (toutes les 2 min) dans `ClaudeTrace.csv` — les deux pourcentages et leurs variations, les dates de reset, le temps d'inactivité clavier/souris, et le nombre de processus Claude Code actifs sur la machine. Ça permet de répondre à la question « la conso a-t-elle monté cette nuit, et à cause de quoi ? ». Ouvrable directement via le **clic-droit → « Ouvrir le journal de diagnostic »**, désactivable par la case juste au-dessus.

  > Le widget lui-même ne consomme **aucun token** : il ne fait qu'un `GET` de lecture sur l'endpoint de consommation, plus un `POST` de rafraîchissement du jeton OAuth. Les deux barres affichent des **fenêtres glissantes sur la consommation passée** — la barre 7 jours ne redescend donc pas parce qu'on arrête de travailler.

## 🚀 Nouveautés v1.42(s)

- **Raccourci Global** : Appuyez sur `Ctrl + Maj + C` de n'importe où pour cacher ou afficher le widget flottant instantanément !
- **Notifications & Son** : Recevez une bulle de notification Windows et un son (`tada.wav`) quand vos tokens de session sont restaurés.
- **Thèmes & Personnalisation** : Clic-droit pour changer de thème !
  - *Normal* (gris classique) — un son « pika pika » joué **au lancement**
  - *Rainbow* (dégradé arc-en-ciel + **Nyan Cat animé** et sa **musique en boucle**)
  - *Nintendo 64* (fond gris clair, barre 4 couleurs N64)
  - *Gamecube* (fond Indigo, barre orange)
  - *DJ* (Rose Playboy, visage ( ๏ )( ๏ ) qui se dandine avec un « Boing Boing » + un son joué **à la sélection**)
  - *888* (palette maussade, visage 8=D dont la langue s'allonge avec la conso)
- **Mémorisation du thème** : le widget rouvre automatiquement sur le **dernier thème utilisé** avant fermeture.
- **Sons & musique des thèmes** : Nyan Cat en boucle (Rainbow), un son à la sélection (DJ), un son au démarrage (Défaut) — le tout désactivable via le clic-droit (« Activer la musique des thèmes »).
- **Mode Fantôme** : Rend le widget flottant semi-transparent (50%) pour ne pas gêner votre code.
- **Mascottes animées à fond transparent** : un Pikachu (thèmes classiques) ou un Nyan Cat (Rainbow) court le long de votre barre de session.
- **Historique** : Génère un journal d'utilisation `ClaudeHistory.log` pour suivre l'heure exacte de vos limites et renouvellements.
- **Robustesse (v1.42(s))** : écriture **atomique et sans BOM** du fichier d'identifiants de Claude Code (jamais corrompu, même si le widget est fermé en plein rafraîchissement), réponses API validées avant usage, et un rafraîchissement raté n'écrase plus les identifiants.

---

## Prérequis

Sur chaque PC où tu veux utiliser le widget :

1. **Claude Code** installé.
2. Être **connecté à ton compte Claude**. Si tu as déjà connecté Claude Code dans ton terminal (PowerShell ou Git Bash), c'est bon — pas besoin de refaire `/login`. Sinon, lance `claude` une première fois et fais `/login`.

Le widget lit le fichier de session `~/.claude/.credentials.json` et rafraîchit le jeton OAuth automatiquement quand il expire. Il n'écrit jamais de secret ailleurs.

---

## Utilisation rapide

Le plus simple — double-clique sur **`ClaudeWidget.exe`** (fichier unique, icône et Pikachu intégrés).

> Au tout premier lancement, Windows SmartScreen peut afficher « Windows a protégé votre PC » car l'exécutable n'est pas signé.
> Clique **Informations complémentaires** → **Exécuter quand même** (une seule fois par PC).

- **Déplacer** le widget : clique-glisse dessus.
- **Fermer** le widget : la croix ✕ en haut à droite, ou via l'icône de la barre des tâches.

---

## Lancement automatique au démarrage

1. Copie d'abord le dossier sur le **disque du PC** (par ex. dans `Documents`) — pas depuis une clé USB, sinon le widget ne se lancera que si la clé est branchée.
2. Lance `powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1` (le widget flottant se lancera à l'ouverture de session).

Pour désactiver : `powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1 -Remove` (ou supprime le raccourci « Claude Usage Widget.lnk » dans `shell:startup`).

---

## Contenu du dépôt

| Fichier | Rôle |
|---------|------|
| `ClaudeWidget.exe` | Le widget flottant, fichier unique 100 % autonome (Pikachu transparent, Nyan Cat, musiques et sons intégrés). |
| `ClaudeUsageWidget.ps1` | Code du widget flottant (WPF / PowerShell). |
| `ClaudeWidget.vbs` | Lanceur silencieux du script. |
| `Installer-Demarrage.ps1` | Active / désactive le lancement au démarrage. |
| `ClaudeTrace.csv` | Journal de diagnostic généré à l'exécution (une ligne par relève, non versionné, rotation à 5 Mo). |
| `pikachu-cours-trans.gif` / `nyan-cat.gif` | Sprites animés à fond transparent (sources ; déjà intégrés dans `ClaudeWidget.exe`). |
| `Build-Exe.ps1` | Recompile `ClaudeWidget.exe` depuis le script (paramètres ps2exe figés, test de démarrage, signature). |
| `Sign-Widget.ps1` | Signe `ClaudeWidget.exe` avec un certificat de signature de code. |
| `Build-Icon.ps1` | Génère `claude.ico`. |
| `claude.ico` | Icône du widget. |
| `tools/` | Source de la musique Nyan Cat (`.mid`) et script de rendu chiptune (`render-nyan.py`). |
| `archives/` | Ancien widget « zone de notification » (`ClaudeTrayWidget`), plus maintenu. |

---

## Fonctionnement technique

- `Get-Creds` lit `~/.claude/.credentials.json` ; `Get-Token` / `Refresh-Token` gèrent le jeton OAuth (`client_id` public de Claude Code, `grant_type=refresh_token`).
- La consommation est récupérée sur `https://api.anthropic.com/api/oauth/usage` (en-tête `anthropic-beta: oauth-2025-04-20`), champs `five_hour.utilization` et `seven_day.utilization`.
- L'interface est en **WPF** (PowerShell).
- La position, la taille et le dernier thème sont mémorisés dans `widget_pos.json`.
- Les sprites (GIF) et sons (WAV) sont embarqués en base64 dans le script/`.exe` : aucun fichier annexe requis. Les GIF animés sont décodés via GDI+ pour préserver la transparence.

---

## Recompiler et signer l'exe

```powershell
.\Build-Exe.ps1 -Thumbprint BC853BE5663319E62A1E0F5B6F1D132AD42A6522
```

`Build-Exe.ps1` fige les paramètres ps2exe (dont `-STA`, sans lequel l'exe se termine en silence au démarrage), lit le numéro de version dans le XAML du widget, lance l'exe pour vérifier que la fenêtre charge, puis délègue la signature à `Sign-Widget.ps1`.

> ps2exe n'est pas déterministe : deux compilations du même source produisent deux SHA-256 différents. Le script fige les *paramètres*, pas le binaire. L'authenticité repose sur la signature, pas sur le hash.

### Certificat de signature

L'exe est signé avec un certificat **auto-signé** et horodaté (l'horodatage maintient la signature valide après expiration du certificat) :

```
CN=Julien Capone (Widget Claude), O=DIDEE-EMS
Empreinte : BC853BE5663319E62A1E0F5B6F1D132AD42A6522
Expire    : 2031-07-09
```

`Get-AuthenticodeSignature` renvoie `Status: UnknownError` sur un auto-signé — c'est normal, la racine n'est pas approuvée. Sur les postes qui déclenchent des faux positifs, importer le certificat dans **Éditeurs approuvés** suffit.

### Si le certificat a disparu du magasin

La clé privée n'existe **que** dans `Cert:\CurrentUser\My` du poste qui a émis le certificat. Sauvegarde-la, hors du dépôt (`*.pfx` est ignoré par Git) :

```powershell
Export-PfxCertificate -Cert Cert:\CurrentUser\My\BC853BE5663319E62A1E0F5B6F1D132AD42A6522 `
    -FilePath "$env:USERPROFILE\Documents\widget-signing.pfx" `
    -Password (Read-Host 'Mot de passe' -AsSecureString)
```

Pour re-signer depuis cette sauvegarde :

```powershell
.\Sign-Widget.ps1 -PfxPath "$env:USERPROFILE\Documents\widget-signing.pfx"
```

Sans le `.pfx`, il faut émettre un **nouveau** certificat (`New-SelfSignedCertificate -Type CodeSigningCert`). Son empreinte sera différente : les postes qui avaient approuvé l'ancien devront réapprouver le nouveau. C'est exactement ce qui est arrivé entre la v1.42(s) et la v1.42(x).

---

## Licence

Voir le fichier [LICENSE](LICENSE).
