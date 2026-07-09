<#
.SYNOPSIS
    Compile ClaudeUsageWidget.ps1 en ClaudeWidget.exe, puis (optionnellement) le signe.

.DESCRIPTION
    Fige les parametres ps2exe du widget, qui ne sont devinables nulle part ailleurs :

      -noConsole  le widget est une fenetre WPF, pas une appli console
      -STA        WPF exige un thread en apartment monofil ; sans ca l'exe
                  se termine silencieusement au demarrage
      -iconFile   claude.ico
      -title      devient FileDescription dans les proprietes du fichier

    Le numero de version est lu directement dans le XAML du widget (le TextBlock
    "v1.42(x)"), pour qu'il ne puisse pas diverger de ce qu'affiche la fenetre.

    Etapes : arret du widget (il verrouille son propre exe) -> compilation ->
    test de demarrage -> signature -> relance si le widget tournait.

.PARAMETER Thumbprint
    Empreinte d'un certificat de signature. Si absent, l'exe est laisse non signe
    (et un avertissement est affiche : un exe non signe declenche des faux positifs).

.PARAMETER SkipSmokeTest
    N'execute pas l'exe apres compilation. A eviter : c'est le seul controle qui
    detecte un -STA manquant ou un XAML casse.

.EXAMPLE
    # Compilation + signature (cas normal)
    .\Build-Exe.ps1 -Thumbprint BC853BE5663319E62A1E0F5B6F1D132AD42A6522

.EXAMPLE
    # Compilation seule, pour tester une modif locale
    .\Build-Exe.ps1
#>
[CmdletBinding()]
param(
    [string]$Thumbprint,
    [switch]$SkipSmokeTest,
    [string]$InputFile,
    [string]$OutputFile,
    [string]$IconFile
)

$ErrorActionPreference = 'Stop'

# Resolus dans le corps : avec [CmdletBinding()], PowerShell 5.1 evalue les
# defauts de parametres avant de peupler $PSScriptRoot.
$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $InputFile)  { $InputFile  = Join-Path $root 'ClaudeUsageWidget.ps1' }
if (-not $OutputFile) { $OutputFile = Join-Path $root 'ClaudeWidget.exe' }
if (-not $IconFile)   { $IconFile   = Join-Path $root 'claude.ico' }

foreach ($f in @($InputFile, $IconFile)) {
    if (-not (Test-Path $f)) { throw "Introuvable : $f" }
}

# ---------- 1. Prerequis ----------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    throw "Module ps2exe absent. Installe-le : Install-Module ps2exe -Scope CurrentUser"
}
Import-Module ps2exe

# ---------- 2. Version, lue dans le XAML du widget ----------
# <TextBlock Text="v1.42(x)" .../>  ->  affichage "v1.42(x)", FileVersion "1.42.0.0"
$src = Get-Content $InputFile -Raw -Encoding UTF8
$m = [regex]::Match($src, 'Text="v(?<maj>\d+)\.(?<min>\d+)(?<suffix>\([a-z]\))?"')
if (-not $m.Success) { throw "Impossible de lire la version dans le XAML de $InputFile" }
$displayVersion = "v$($m.Groups['maj'].Value).$($m.Groups['min'].Value)$($m.Groups['suffix'].Value)"
$fileVersion    = "$($m.Groups['maj'].Value).$($m.Groups['min'].Value).0.0"
Write-Host "Version    : $displayVersion  (FileVersion $fileVersion)" -ForegroundColor Cyan

# ---------- 3. Arreter le widget : il verrouille son propre exe ----------
$wasRunning = $false
$proc = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile)) -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Arret du widget (PID $($proc.Id -join ', '))..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    Start-Sleep -Milliseconds 900
    $wasRunning = $true
}

# ---------- 4. Compiler ----------
Write-Host "Compilation..." -ForegroundColor Cyan
Invoke-ps2exe -inputFile $InputFile -outputFile $OutputFile -iconFile $IconFile `
              -noConsole -STA `
              -title 'Claude Usage Widget' `
              -product 'Widget Claude' `
              -version $fileVersion

if (-not (Test-Path $OutputFile)) { throw "ps2exe n'a produit aucun fichier." }
$exe = Get-Item $OutputFile
Write-Host ("Ecrit      : {0} ({1:N2} Mo)" -f $exe.Name, ($exe.Length / 1MB)) -ForegroundColor Green

# ---------- 5. Test de demarrage ----------
# Un -STA manquant ou un XAML invalide se traduit par un exe qui se termine
# immediatement, sans message. C'est le seul moyen de le detecter.
if (-not $SkipSmokeTest) {
    Write-Host "Test de demarrage..." -ForegroundColor Cyan
    $p = Start-Process $OutputFile -PassThru
    Start-Sleep -Seconds 6
    if ($p.HasExited) {
        throw "L'exe s'est termine seul (code $($p.ExitCode)). Fenetre WPF non chargee : verifie -STA et le XAML."
    }
    Write-Host "OK : la fenetre est chargee, le processus tient." -ForegroundColor Green
    Stop-Process -Id $p.Id -Force
    Start-Sleep -Milliseconds 700
}

# ---------- 6. Signer ----------
if ($Thumbprint) {
    $signScript = Join-Path $root 'Sign-Widget.ps1'
    if (-not (Test-Path $signScript)) { throw "Introuvable : $signScript" }
    Write-Host "Signature..." -ForegroundColor Cyan
    & $signScript -Thumbprint $Thumbprint -ExePath $OutputFile
} else {
    Write-Warning "Exe NON SIGNE. Kaspersky et SmartScreen risquent de le signaler."
    Write-Warning "Relance avec -Thumbprint <empreinte>, ou lance Sign-Widget.ps1 ensuite."
}

# ---------- 7. Recapitulatif ----------
$sig = Get-AuthenticodeSignature $OutputFile
Write-Host ""
Write-Host "=== Recapitulatif ===" -ForegroundColor Cyan
Write-Host "Version    : $displayVersion"
Write-Host "SHA-256    : $((Get-FileHash $OutputFile -Algorithm SHA256).Hash)"
if ($sig.SignerCertificate) {
    Write-Host "Signataire : $($sig.SignerCertificate.Subject)"
    # 'UnknownError' = certificat auto-signe (racine non approuvee). Attendu.
    Write-Host "Status     : $($sig.Status)"
} else {
    Write-Host "Signataire : (aucun)"
}

# ---------- 8. Relancer si le widget tournait ----------
# Sign-Widget.ps1 ne relance rien ici : on l'avait deja arrete a l'etape 3.
if ($wasRunning -and -not (Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile)) -ErrorAction SilentlyContinue)) {
    Start-Process $OutputFile
    Write-Host "Widget relance." -ForegroundColor Green
}
