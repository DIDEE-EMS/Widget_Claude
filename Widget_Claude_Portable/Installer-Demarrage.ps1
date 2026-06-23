# Ajoute (ou retire) le widget au démarrage de Windows.
#   Activer  :  powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1
#   Désactiver: powershell -ExecutionPolicy Bypass -File Installer-Demarrage.ps1 -Remove
param([switch]$Remove)

$startup  = [Environment]::GetFolderPath('Startup')
$lnkPath  = Join-Path $startup 'Claude Usage Widget.lnk'
$vbs      = Join-Path $PSScriptRoot 'ClaudeWidget.vbs'

if ($Remove) {
    if (Test-Path $lnkPath) { Remove-Item $lnkPath; Write-Host "Démarrage auto désactivé." }
    else { Write-Host "Aucun raccourci de démarrage trouvé." }
    return
}

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath  = 'wscript.exe'
$lnk.Arguments   = '"' + $vbs + '"'
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.IconLocation = 'powershell.exe,0'
$lnk.Description  = 'Widget de consommation Claude'
$lnk.Save()
Write-Host "Démarrage auto activé : le widget se lancera à l'ouverture de session."
