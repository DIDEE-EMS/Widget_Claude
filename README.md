# Widget Claude

Widget de bureau pour Windows 11 qui affiche **en direct ta consommation Claude** : la fenêtre de session (5 h) et le quota hebdomadaire (7 jours), avec le temps restant avant chaque reset.

Les données sont lues via la session **Claude Code** déjà présente sur le PC (API OAuth de consommation). Aucun mot de passe ni jeton n'est stocké par le widget : il réutilise uniquement les identifiants existants de Claude Code.

---

## Aperçu

<p align="center">
  <img src="docs/widget.png" alt="Widget Claude posé sur le bureau, affichant la consommation Session et Semaine" width="340">
</p>

Deux affichages au choix :

| Mode | Fichier | Description |
|------|---------|-------------|
| **Flottant** | `ClaudeWidget.exe` | Petit panneau posé sur le bureau, déplaçable au clic-glissé (position mémorisée). |
| **Zone de notification** | `ClaudeTray.vbs` | Icône près de l'horloge (style DuMeter) : survol = détail, clic gauche = panneau, clic droit = menu. |

Barres de couleur : 🟢 vert < 50 %, 🟠 ambre 50–85 %, 🔴 rouge > 85 %.
Les données se rafraîchissent automatiquement toutes les 2 minutes.

---

## Prérequis

Sur chaque PC où tu veux utiliser le widget :

1. **Claude Code** installé.
2. Être **connecté à ton compte Claude** : lance `claude` puis `/login`.

Le widget lit le fichier de session `~/.claude/.credentials.json` et rafraîchit le jeton OAuth automatiquement quand il expire. Il n'écrit jamais de secret ailleurs.

---

## Utilisation rapide

Le plus simple — double-clique sur **`ClaudeWidget.exe`** (fichier unique, icône intégrée).

> Au tout premier lancement, Windows SmartScreen peut afficher « Windows a protégé votre PC » car l'exécutable n'est pas signé.
> Clique **Informations complémentaires** → **Exécuter quand même** (une seule fois par PC).

Tu peux aussi lancer sans le `.exe` via **`Lancer Widget Claude.vbs`** (lancement silencieux du script PowerShell).

- **Déplacer** le widget : clique-glisse dessus.
- **Fermer** le widget : la croix ✕ en haut à droite.

---

## Lancement automatique au démarrage

1. Copie d'abord le dossier sur le **disque du PC** (par ex. dans `Documents`) — pas depuis une clé USB, sinon le widget ne se lancera que si la clé est branchée.
2. Double-clique sur **`Activer demarrage auto.vbs`**.

Cela crée un raccourci dans le dossier Démarrage de Windows. Équivalent en ligne de commande :

```powershell
# Activer
powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1
# Désactiver
powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1 -Remove
```

Pour désactiver manuellement : supprime le raccourci « Claude Usage Widget » dans `shell:startup` (touche Windows + R → `shell:startup`).

> **À savoir au démarrage**
> - Pour que les valeurs s'affichent, il faut **être connecté à Claude** (Claude Code installé et session active via `claude` → `/login`). Sans connexion, le widget affiche « Non connecté à Claude ».
> - Les pourcentages peuvent mettre **2 à 3 minutes** à apparaître après que tu aies **commencé à travailler sur un projet avec Claude** : le widget interroge l'API toutes les 2 minutes, et la consommation côté serveur n'est mise à jour qu'une fois l'activité prise en compte.

---

## Contenu du dépôt

| Fichier | Rôle |
|---------|------|
| `ClaudeWidget.exe` | Le widget flottant en un seul fichier (le plus simple). |
| `ClaudeUsageWidget.ps1` | Code du widget flottant (WPF / PowerShell). |
| `ClaudeTrayWidget.ps1` | Code de la version icône (zone de notification). |
| `ClaudeWidget.vbs` / `ClaudeTray.vbs` | Lanceurs silencieux des scripts ci-dessus. |
| `Installer-Demarrage.ps1` | Ajoute / retire le widget du démarrage de Windows. |
| `Build-Icon.ps1` | Génère `claude.ico`. |
| `claude.ico` | Icône du widget. |
| `Widget_Claude_Portable/` | Version prête à copier sur clé USB (mêmes fichiers + `LISEZMOI.txt`). |

---

## Fonctionnement technique

- `Get-Creds` lit `~/.claude/.credentials.json` ; `Get-Token` / `Refresh-Token` gèrent le jeton OAuth (`client_id` public de Claude Code, `grant_type=refresh_token`).
- La consommation est récupérée sur `https://api.anthropic.com/api/oauth/usage` (en-tête `anthropic-beta: oauth-2025-04-20`), champs `five_hour.utilization` et `seven_day.utilization`.
- L'interface est en **WPF** via PowerShell ; la position de la fenêtre est sauvegardée dans `~/.claude/widget-pos.json`.

---

## Licence

Voir le fichier [LICENSE](LICENSE).
