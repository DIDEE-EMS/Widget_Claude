<#
.SYNOPSIS
    Signe ClaudeWidget.exe avec un certificat de signature de code.

.DESCRIPTION
    Arrete le widget s'il tourne (il verrouille son propre exe), signe l'exe
    avec horodatage, verifie, puis relance le widget.

    Fonctionne avec :
      - un certificat present dans le magasin (auto-signe ou reel), via -Thumbprint
      - un fichier .pfx (cert reel exporte), via -PfxPath / -PfxPassword

    Le moment venu (certificat reconnu type Microsoft Trusted Signing ou
    Certum Open Source), il suffira de relancer ce script avec le bon -Thumbprint.

.EXAMPLE
    # Auto-signe actuel (magasin CurrentUser\My)
    .\Sign-Widget.ps1 -Thumbprint A5A8EBF228F2299EE618462D48DA5AC3C89FC775

.EXAMPLE
    # Avec un vrai certificat exporte en .pfx
    .\Sign-Widget.ps1 -PfxPath .\mon-cert.pfx -PfxPassword (Read-Host -AsSecureString)
#>
[CmdletBinding(DefaultParameterSetName = 'Store')]
param(
    [Parameter(ParameterSetName = 'Store', Mandatory)]
    [string]$Thumbprint,

    [Parameter(ParameterSetName = 'Pfx', Mandatory)]
    [string]$PfxPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [System.Security.SecureString]$PfxPassword,

    [string]$ExePath = (Join-Path $PSScriptRoot 'ClaudeWidget.exe'),

    # Serveurs d'horodatage RFC3161 (l'horodatage garde la signature valide
    # apres expiration du certificat). On essaie le second si le premier echoue.
    [string[]]$TimestampServers = @(
        'http://timestamp.digicert.com',
        'http://timestamp.sectigo.com'
    )
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ExePath)) { throw "Introuvable : $ExePath" }

# 1. Recuperer le certificat
if ($PSCmdlet.ParameterSetName -eq 'Pfx') {
    if (-not $PfxPassword) { $PfxPassword = Read-Host 'Mot de passe du .pfx' -AsSecureString }
    $cert = Get-PfxCertificate -FilePath $PfxPath -Password $PfxPassword
} else {
    $cert = Get-Item "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) { $cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue }
    if (-not $cert) { throw "Certificat $Thumbprint introuvable dans les magasins My." }
}
Write-Host "Certificat : $($cert.Subject)" -ForegroundColor Cyan

# 2. Arreter le widget s'il tourne (il verrouille l'exe)
$wasRunning = $false
$proc = Get-Process ClaudeWidget -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Arret du widget (PID $($proc.Id))..." -ForegroundColor Yellow
    $proc | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    $wasRunning = $true
}

# 3. Signer (avec horodatage, on tente chaque serveur)
$signed = $false
foreach ($ts in $TimestampServers) {
    $res = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert `
        -TimestampServer $ts -HashAlgorithm SHA256
    if ($res.TimeStamperCertificate) {
        Write-Host "Signe + horodate via $ts" -ForegroundColor Green
        $signed = $true
        break
    }
    Write-Host "Horodatage echoue via $ts, essai suivant..." -ForegroundColor Yellow
}
if (-not $signed) { Write-Warning "Signe sans horodatage (aucun serveur TS n'a repondu)." }

# 4. Verifier
$sig = Get-AuthenticodeSignature $ExePath
Write-Host ""
Write-Host "Status    : $($sig.Status)"          # 'Valid' avec un vrai cert ; 'UnknownError' avec un auto-signe (racine non approuvee) = normal
Write-Host "Signataire: $($sig.SignerCertificate.Subject)"
Write-Host "SHA-256   : $((Get-FileHash $ExePath -Algorithm SHA256).Hash)"

# 5. Relancer si necessaire
if ($wasRunning) {
    Start-Process $ExePath
    Write-Host "Widget relance." -ForegroundColor Green
}
