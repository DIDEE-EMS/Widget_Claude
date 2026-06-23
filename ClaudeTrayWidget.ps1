# ============================================================
#  Claude Tray Widget  -  zone de notification (style DuMeter)
#  Icône vivante (2 barres : session 5h + hebdo 7j),
#  tooltip au survol, panneau détaillé au clic, menu clic-droit.
#  Lancer : powershell -ExecutionPolicy Bypass -File ClaudeTrayWidget.ps1
#  (ou via ClaudeTray.vbs pour un lancement silencieux)
# ============================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class IconUtil { [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h); }
"@

# ---------- Config ----------
$CredPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$ClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
$TokenUrl = 'https://console.anthropic.com/v1/oauth/token'
$UsageUrl = 'https://api.anthropic.com/api/oauth/usage'
$StartLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Usage Widget.lnk'
$PollMs   = 120000   # 2 min

# ---------- Données (token + usage) ----------
function Get-Creds { if (Test-Path $CredPath) { try { Get-Content $CredPath -Raw | ConvertFrom-Json } catch {} } }
function Save-Creds($o) { try { $o | ConvertTo-Json -Depth 10 | Set-Content $CredPath -Encoding UTF8 } catch {} }
function NowMs { [int64]((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01')).TotalMilliseconds }

function Refresh-Token {
    $c = Get-Creds; if (-not $c) { return $null }
    $o = $c.claudeAiOauth
    $body = @{ grant_type='refresh_token'; refresh_token=$o.refreshToken; client_id=$ClientId } | ConvertTo-Json
    try { $r = Invoke-RestMethod -Uri $TokenUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20 } catch { return $null }
    $o.accessToken = $r.access_token
    if ($r.refresh_token) { $o.refreshToken = $r.refresh_token }
    $o.expiresAt = (NowMs) + ($r.expires_in * 1000)
    $c.claudeAiOauth = $o; Save-Creds $c
    return $o.accessToken
}
function Get-Token {
    $c = Get-Creds; if (-not $c) { return $null }
    $o = $c.claudeAiOauth
    if (-not $o.accessToken -or ($o.expiresAt - (NowMs)) -lt 60000) { return (Refresh-Token) }
    return $o.accessToken
}
function Invoke-Usage($t) {
    Invoke-RestMethod -Uri $UsageUrl -Method Get -TimeoutSec 20 -Headers @{ Authorization="Bearer $t"; 'anthropic-beta'='oauth-2025-04-20' }
}
function Get-Usage {
    $t = Get-Token; if (-not $t) { return @{ ok=$false; err='Non connecté à Claude' } }
    try { $u = Invoke-Usage $t }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            $t = Refresh-Token; if (-not $t) { return @{ ok=$false; err='Reconnexion requise' } }
            try { $u = Invoke-Usage $t } catch { return @{ ok=$false; err='Erreur API' } }
        } else { return @{ ok=$false; err='Hors ligne' } }
    }
    @{ ok=$true
       sessionPct=[double]$u.five_hour.utilization; sessionRst=$u.five_hour.resets_at
       weekPct=[double]$u.seven_day.utilization;    weekRst=$u.seven_day.resets_at }
}

# ---------- Helpers ----------
function Format-Countdown($iso) {
    if (-not $iso) { return '?' }
    try { $t = ([datetimeoffset]$iso).LocalDateTime } catch { return '?' }
    $s = $t - (Get-Date)
    if ($s.TotalSeconds -le 0) { return 'maintenant' }
    if ($s.TotalDays  -ge 1) { return ('{0}j {1}h'   -f [int]$s.TotalDays,  $s.Hours) }
    if ($s.TotalHours -ge 1) { return ('{0}h {1}min' -f [int]$s.TotalHours, $s.Minutes) }
    return ('{0} min' -f [int]$s.TotalMinutes)
}
function Pct-Color([double]$p) {
    if ($p -ge 85) { return [System.Drawing.ColorTranslator]::FromHtml('#F87171') }
    if ($p -ge 50) { return [System.Drawing.ColorTranslator]::FromHtml('#FBBF24') }
    return [System.Drawing.ColorTranslator]::FromHtml('#4ADE80')
}

# ---------- Dessin de l'icône (2 barres horizontales) ----------
$script:lastHIcon = [IntPtr]::Zero
function New-TrayIcon([double]$sess, [double]$week, [bool]$ok) {
    $sz = 32
    $bmp = New-Object System.Drawing.Bitmap $sz, $sz
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # fond sombre arrondi pour bien ressortir dans la barre des taches
    $bg = New-Object System.Drawing.Drawing2D.GraphicsPath
    $r = 7; $d = $r*2
    $bg.AddArc(1,1,$d,$d,180,90); $bg.AddArc(($sz-$d-2),1,$d,$d,270,90)
    $bg.AddArc(($sz-$d-2),($sz-$d-2),$d,$d,0,90); $bg.AddArc(1,($sz-$d-2),$d,$d,90,90); $bg.CloseFigure()
    $bgB = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,27,27,31))
    $g.FillPath($bgB, $bg); $bgB.Dispose(); $bg.Dispose()

    $x = 5; $w = 22; $h = 8
    $track = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70,255,255,255))
    if ($ok) {
        # barre session (haut)
        $g.FillRectangle($track, $x, 7, $w, $h)
        $b1 = New-Object System.Drawing.SolidBrush (Pct-Color $sess)
        $g.FillRectangle($b1, $x, 7, [int]([Math]::Max(0.04,[Math]::Min(1,$sess/100))*$w), $h); $b1.Dispose()
        # barre semaine (bas)
        $g.FillRectangle($track, $x, 18, $w, $h)
        $b2 = New-Object System.Drawing.SolidBrush (Pct-Color $week)
        $g.FillRectangle($b2, $x, 18, [int]([Math]::Max(0.04,[Math]::Min(1,$week/100))*$w), $h); $b2.Dispose()
    } else {
        $dim = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120,150,150,160))
        $g.FillRectangle($dim, $x, 7, $w, $h); $g.FillRectangle($dim, $x, 18, $w, $h); $dim.Dispose()
    }
    $track.Dispose(); $g.Dispose()

    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    if ($script:lastHIcon -ne [IntPtr]::Zero) { [IconUtil]::DestroyIcon($script:lastHIcon) | Out-Null }
    $script:lastHIcon = $h
    $bmp.Dispose()
    return $icon
}

# ---------- NotifyIcon ----------
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = (New-TrayIcon 0 0 $false)
$notify.Text = 'Claude — chargement…'
$notify.Visible = $true

# ---------- Menu clic-droit ----------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miRefresh = $menu.Items.Add('Rafraîchir maintenant')
$miStartup = New-Object System.Windows.Forms.ToolStripMenuItem 'Démarrage automatique'
$miStartup.CheckOnClick = $true
$miStartup.Checked = (Test-Path $StartLnk)
[void]$menu.Items.Add($miStartup)
[void]$menu.Items.Add('-')
$miQuit = $menu.Items.Add('Quitter')
$notify.ContextMenuStrip = $menu

# ---------- Panneau détaillé (clic gauche) ----------
$pop = New-Object System.Windows.Forms.Form
$pop.FormBorderStyle = 'None'; $pop.ShowInTaskbar = $false; $pop.TopMost = $true
$pop.StartPosition = 'Manual'; $pop.Size = New-Object System.Drawing.Size 250,128
$pop.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#1B1B1F')
function New-Lbl($txt,$x,$y,$w,$col,$size,$bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text=$txt; $l.AutoSize=$false; $l.Location=New-Object System.Drawing.Point $x,$y
    $l.Size=New-Object System.Drawing.Size $w,18
    $l.ForeColor=[System.Drawing.ColorTranslator]::FromHtml($col)
    $st=if($bold){[System.Drawing.FontStyle]::Bold}else{[System.Drawing.FontStyle]::Regular}
    $l.Font=New-Object System.Drawing.Font 'Segoe UI',$size,$st
    $pop.Controls.Add($l); return $l
}
function New-Bar($x,$y) {
    $tr=New-Object System.Windows.Forms.Panel; $tr.Location=New-Object System.Drawing.Point $x,$y
    $tr.Size=New-Object System.Drawing.Size 222,7; $tr.BackColor=[System.Drawing.Color]::FromArgb(60,255,255,255)
    $fl=New-Object System.Windows.Forms.Panel; $fl.Location=New-Object System.Drawing.Point 0,0
    $fl.Size=New-Object System.Drawing.Size 0,7; $tr.Controls.Add($fl); $pop.Controls.Add($tr)
    return $fl
}
$lblTitle = New-Lbl 'Claude' 14 10 150 '#FFFFFF' 11 $true
$lblSessT = New-Lbl 'Session (5 h)' 14 34 120 '#B8B8C0' 9 $false
$lblSessP = New-Lbl '—' 150 34 86 '#FFFFFF' 9 $true; $lblSessP.TextAlign='MiddleRight'
$barSess  = New-Bar 14 54
$lblSessR = New-Lbl '' 14 63 222 '#7C7C88' 8 $false
$lblWeekT = New-Lbl 'Semaine (7 j)' 14 84 120 '#B8B8C0' 9 $false
$lblWeekP = New-Lbl '—' 150 84 86 '#FFFFFF' 9 $true; $lblWeekP.TextAlign='MiddleRight'
$barWeek  = New-Bar 14 104
$lblWeekR = New-Lbl '' 14 113 222 '#7C7C88' 8 $false
$pop.Add_Deactivate({ $pop.Hide() })

# ---------- État + rafraîchissement ----------
function Refresh-All {
    $d = Get-Usage
    if ($d.ok) {
        $notify.Icon = (New-TrayIcon $d.sessionPct $d.weekPct $true)
        $sr = Format-Countdown $d.sessionRst; $wr = Format-Countdown $d.weekRst
        $notify.Text = ("Session {0:0}% · reset {1}`nSemaine {2:0}% · reset {3}" -f $d.sessionPct,$sr,$d.weekPct,$wr)
        if ($notify.Text.Length -gt 127) { $notify.Text = $notify.Text.Substring(0,127) }
        $lblSessP.Text = ('{0:0}%' -f $d.sessionPct); $lblWeekP.Text = ('{0:0}%' -f $d.weekPct)
        $lblSessR.Text = "reset dans $sr"; $lblWeekR.Text = "reset dans $wr"
        $barSess.Width = [int]([Math]::Max(0,[Math]::Min(1,$d.sessionPct/100))*222)
        $barWeek.Width = [int]([Math]::Max(0,[Math]::Min(1,$d.weekPct/100))*222)
        $barSess.BackColor = (Pct-Color $d.sessionPct); $barWeek.BackColor = (Pct-Color $d.weekPct)
    } else {
        $notify.Icon = (New-TrayIcon 0 0 $false)
        $notify.Text = "Claude — $($d.err)"
        $lblSessP.Text='—'; $lblWeekP.Text='—'; $lblSessR.Text=$d.err; $lblWeekR.Text=''
        $barSess.Width=0; $barWeek.Width=0
    }
}

function Show-Pop {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $pop.Location = New-Object System.Drawing.Point (($wa.Right - $pop.Width - 8), ($wa.Bottom - $pop.Height - 8))
    $pop.Show(); $pop.Activate()
}

# ---------- Événements ----------
$notify.Add_MouseClick({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { if ($pop.Visible) { $pop.Hide() } else { Refresh-All; Show-Pop } } })
$miRefresh.Add_Click({ Refresh-All })
$miStartup.Add_Click({
    if ($miStartup.Checked) {
        $ws=New-Object -ComObject WScript.Shell; $lnk=$ws.CreateShortcut($StartLnk)
        $lnk.TargetPath='wscript.exe'; $lnk.Arguments='"'+(Join-Path $PSScriptRoot 'ClaudeTray.vbs')+'"'
        $lnk.WorkingDirectory=$PSScriptRoot; $lnk.IconLocation='powershell.exe,0'; $lnk.Save()
    } elseif (Test-Path $StartLnk) { Remove-Item $StartLnk }
})
$miQuit.Add_Click({
    $timer.Stop(); $notify.Visible=$false; $notify.Dispose()
    if ($script:lastHIcon -ne [IntPtr]::Zero) { [IconUtil]::DestroyIcon($script:lastHIcon) | Out-Null }
    [System.Windows.Forms.Application]::Exit()
})

# ---------- Timer ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollMs
$timer.Add_Tick({ Refresh-All })
$timer.Start()

Refresh-All
[System.Windows.Forms.Application]::Run()
