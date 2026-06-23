# ============================================================
#  Claude Usage Widget  -  bureau Windows 11
#  Affiche la conso Session (5h) + Hebdo (7j) + reset
#  Lance avec : powershell -ExecutionPolicy Bypass -File ClaudeUsageWidget.ps1
#  (ou via ClaudeWidget.vbs pour un lancement silencieux)
# ============================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ---------- Config ----------
$CredPath   = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$PosPath    = Join-Path $env:USERPROFILE '.claude\widget-pos.json'
$ClientId   = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'
$TokenUrl   = 'https://console.anthropic.com/v1/oauth/token'
$UsageUrl   = 'https://api.anthropic.com/api/oauth/usage'
$PollMs     = 120000   # rafraîchit les données toutes les 2 min

# ---------- Logique données ----------
function Get-Creds {
    if (-not (Test-Path $CredPath)) { return $null }
    try { return Get-Content $CredPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Save-Creds($obj) {
    try { $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $CredPath -Encoding UTF8 } catch {}
}

function Refresh-Token {
    $c = Get-Creds; if (-not $c) { return $null }
    $o = $c.claudeAiOauth
    $body = @{ grant_type='refresh_token'; refresh_token=$o.refreshToken; client_id=$ClientId } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri $TokenUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 20
    } catch { return $null }
    $o.accessToken  = $r.access_token
    if ($r.refresh_token) { $o.refreshToken = $r.refresh_token }
    $o.expiresAt    = [int64]((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01')).TotalMilliseconds + ($r.expires_in * 1000)
    $c.claudeAiOauth = $o
    Save-Creds $c
    return $o.accessToken
}

function Get-Token {
    $c = Get-Creds; if (-not $c) { return $null }
    $o = $c.claudeAiOauth
    $nowMs = [int64]((Get-Date).ToUniversalTime() - (Get-Date '1970-01-01')).TotalMilliseconds
    if (-not $o.accessToken -or ($o.expiresAt - $nowMs) -lt 60000) { return (Refresh-Token) }
    return $o.accessToken
}

function Invoke-Usage($token) {
    $headers = @{ Authorization = "Bearer $token"; 'anthropic-beta' = 'oauth-2025-04-20' }
    return Invoke-RestMethod -Uri $UsageUrl -Method Get -Headers $headers -TimeoutSec 20
}

function Get-Usage {
    $token = Get-Token
    if (-not $token) { return @{ ok=$false; err='Non connecté à Claude' } }
    try {
        $u = Invoke-Usage $token
    } catch {
        # token peut être rejeté -> on tente un refresh une fois
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            $token = Refresh-Token
            if (-not $token) { return @{ ok=$false; err='Reconnexion requise' } }
            try { $u = Invoke-Usage $token } catch { return @{ ok=$false; err='Erreur API' } }
        } else { return @{ ok=$false; err='Hors ligne' } }
    }
    return @{
        ok          = $true
        sessionPct  = [double]$u.five_hour.utilization
        sessionRst  = $u.five_hour.resets_at
        weekPct     = [double]$u.seven_day.utilization
        weekRst     = $u.seven_day.resets_at
    }
}

# ---------- Helpers UI ----------
function Format-Countdown($iso) {
    if (-not $iso) { return '' }
    try { $t = ([datetimeoffset]$iso).LocalDateTime } catch { return '' }
    $span = $t - (Get-Date)
    if ($span.TotalSeconds -le 0) { return 'maintenant' }
    if ($span.TotalDays   -ge 1) { return ('{0}j {1}h'   -f [int]$span.TotalDays, $span.Hours) }
    if ($span.TotalHours  -ge 1) { return ('{0}h {1}min' -f [int]$span.TotalHours, $span.Minutes) }
    return ('{0} min' -f [int]$span.TotalMinutes)
}

function Get-BarColor([double]$pct) {
    if ($pct -ge 85) { return '#F87171' }   # rouge
    if ($pct -ge 50) { return '#FBBF24' }   # ambre
    return '#4ADE80'                         # vert
}

# ---------- Fenêtre (XAML) ----------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        SizeToContent="WidthAndHeight" ResizeMode="NoResize"
        Topmost="True" ShowInTaskbar="False">
  <Grid>
    <Viewbox Stretch="Uniform" StretchDirection="Both">
    <Border Width="280" Background="#EE1B1B1F" CornerRadius="14" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="14">
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
    <StackPanel>
      <Grid>
        <StackPanel Orientation="Horizontal">
          <Ellipse Width="9" Height="9" Fill="#D97757" VerticalAlignment="Center"/>
          <TextBlock Text="Claude" Foreground="#FFFFFF" FontFamily="Segoe UI" FontSize="13"
                     FontWeight="SemiBold" Margin="7,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="BtnClose" Text="✕" Foreground="#888" FontFamily="Segoe UI" FontSize="13"
                   Background="Transparent" Padding="8,2,2,2"
                   HorizontalAlignment="Right" VerticalAlignment="Center" Cursor="Hand"/>
      </Grid>

      <!-- Session -->
      <Grid Margin="0,14,0,0">
        <TextBlock Text="Session (5 h)" Foreground="#B8B8C0" FontFamily="Segoe UI" FontSize="11" VerticalAlignment="Center"/>
        <TextBlock x:Name="SessPct" Text="—" Foreground="#FFFFFF" FontFamily="Segoe UI" FontSize="15"
                   FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
      <Border Background="#3C3C48" CornerRadius="6" Height="12" Margin="0,6,0,0" ClipToBounds="True">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="SessFill" Width="0*"/>
            <ColumnDefinition x:Name="SessEmpty" Width="100*"/>
          </Grid.ColumnDefinitions>
          <Border x:Name="SessBar" Grid.Column="0" Background="#4ADE80" CornerRadius="6"/>
        </Grid>
      </Border>
      <TextBlock x:Name="SessRst" Text="" Foreground="#8A8A96" FontFamily="Segoe UI" FontSize="10" Margin="2,4,0,0"/>

      <!-- Semaine -->
      <Grid Margin="0,12,0,0">
        <TextBlock Text="Semaine (7 j)" Foreground="#B8B8C0" FontFamily="Segoe UI" FontSize="11" VerticalAlignment="Center"/>
        <TextBlock x:Name="WeekPct" Text="—" Foreground="#FFFFFF" FontFamily="Segoe UI" FontSize="15"
                   FontWeight="Bold" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
      <Border Background="#3C3C48" CornerRadius="6" Height="12" Margin="0,6,0,0" ClipToBounds="True">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition x:Name="WeekFill" Width="0*"/>
            <ColumnDefinition x:Name="WeekEmpty" Width="100*"/>
          </Grid.ColumnDefinitions>
          <Border x:Name="WeekBar" Grid.Column="0" Background="#4ADE80" CornerRadius="6"/>
        </Grid>
      </Border>
      <TextBlock x:Name="WeekRst" Text="" Foreground="#8A8A96" FontFamily="Segoe UI" FontSize="10" Margin="2,4,0,0"/>
    </StackPanel>
    </Border>
    </Viewbox>
    <Thumb x:Name="Grip" Width="18" Height="18" HorizontalAlignment="Right" VerticalAlignment="Bottom" Cursor="SizeNWSE">
      <Thumb.Template>
        <ControlTemplate TargetType="Thumb">
          <Border Background="#01FFFFFF">
            <Path Stroke="#9A9AA6" StrokeThickness="1.4" Margin="0,0,4,4"
                  HorizontalAlignment="Right" VerticalAlignment="Bottom"
                  Data="M 6,14 L 14,6 M 9,14 L 14,9 M 12,14 L 14,12"/>
          </Border>
        </ControlTemplate>
      </Thumb.Template>
    </Thumb>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$SessPct = $win.FindName('SessPct'); $SessBar = $win.FindName('SessBar'); $SessRst = $win.FindName('SessRst')
$WeekPct = $win.FindName('WeekPct'); $WeekBar = $win.FindName('WeekBar'); $WeekRst = $win.FindName('WeekRst')
$SessFill = $win.FindName('SessFill'); $SessEmpty = $win.FindName('SessEmpty')
$WeekFill = $win.FindName('WeekFill'); $WeekEmpty = $win.FindName('WeekEmpty')
$BtnClose = $win.FindName('BtnClose')
$Grip     = $win.FindName('Grip')

# ---------- Réglages mémorisés (position + taille) ----------
$win.WindowStartupLocation = 'Manual'
$script:savedLeft = $null; $script:savedTop = $null; $script:savedW = $null
if (Test-Path $PosPath) {
    try { $p = Get-Content $PosPath -Raw | ConvertFrom-Json
          $script:savedLeft = $p.left; $script:savedTop = $p.top; $script:savedW = $p.w } catch {}
}
$script:aspect = 280.0 / 202.0    # ratio provisoire, recalculé après le rendu
$MinW = 180.0; $MaxW = 680.0
$script:inited = $false

# ---------- Fonctions d'état / taille ----------
function Save-State {
    try { @{ left=$win.Left; top=$win.Top; w=$win.Width } | ConvertTo-Json | Set-Content $PosPath } catch {}
}
function Resize-To([double]$w) {
    if ($w -lt $MinW) { $w = $MinW }
    if ($w -gt $MaxW) { $w = $MaxW }
    $win.Width  = $w
    $win.Height = $w / $script:aspect
}
function Is-In($node, $root) {
    $c = $node
    while ($c) { if ($c -eq $root) { return $true }; try { $c = [System.Windows.Media.VisualTreeHelper]::GetParent($c) } catch { break } }
    return $false
}

# ---------- Interactions ----------
# Glisser la fenêtre — sauf depuis la croix ou la poignée de redimensionnement
$win.Add_MouseLeftButtonDown({ param($s,$e)
    if ($e.OriginalSource -eq $BtnClose -or (Is-In $e.OriginalSource $Grip)) { return }
    try { $win.DragMove() } catch {}
})
# Fermeture : on intercepte le clic sur la croix (Handled = stoppe le DragMove)
$BtnClose.Add_MouseLeftButtonDown({ param($s,$e)
    $e.Handled = $true
    Save-State
    $win.Close()
})
$BtnClose.Add_MouseEnter({ $BtnClose.Foreground = '#FFFFFF' })
$BtnClose.Add_MouseLeave({ $BtnClose.Foreground = '#888888' })

# Redimensionnement par la poignée (coin bas-droit)
$Grip.Add_DragDelta({ param($s,$e)
    if ([double]::IsNaN($win.Width)) { $win.Width = $win.ActualWidth }
    Resize-To ($win.Width + $e.HorizontalChange)
})
$Grip.Add_DragCompleted({ Save-State })

# Zoom au Ctrl + molette
$win.Add_MouseWheel({ param($s,$e)
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
        if ([double]::IsNaN($win.Width)) { $win.Width = $win.ActualWidth }
        $step = if ($e.Delta -gt 0) { 24 } else { -24 }
        Resize-To ($win.Width + $step)
        Save-State
        $e.Handled = $true
    }
})

# ---------- État courant pour le countdown ----------
$script:lastSessRst = $null
$script:lastWeekRst = $null
$script:hasData = $false

function Set-Cols($fillCol, $emptyCol, [double]$pct) {
    $p = [Math]::Max(0, [Math]::Min(100, $pct))
    # petit minimum visible dès qu'il y a de la conso
    if ($p -gt 0 -and $p -lt 3) { $p = 3 }
    $star = [System.Windows.GridUnitType]::Star
    $fillCol.Width  = New-Object System.Windows.GridLength $p, $star
    $emptyCol.Width = New-Object System.Windows.GridLength (100 - $p), $star
}

function Update-Bar($bar, $fillCol, $emptyCol, $pctBox, [double]$pct) {
    $pctBox.Text = ('{0:0}%' -f $pct)
    Set-Cols $fillCol $emptyCol $pct
    $bar.Background = (Get-BarColor $pct)
}

function Refresh-Data {
    $d = Get-Usage
    if (-not $d.ok) {
        # erreur transitoire : on garde les dernières valeurs si on en a déjà
        if (-not $script:hasData) {
            $SessPct.Text = '—'; $WeekPct.Text = '—'
            $SessRst.Text = $d.err; $WeekRst.Text = ''
            Set-Cols $SessFill $SessEmpty 0; Set-Cols $WeekFill $WeekEmpty 0
        }
        return
    }
    $script:hasData = $true
    Update-Bar $SessBar $SessFill $SessEmpty $SessPct $d.sessionPct
    Update-Bar $WeekBar $WeekFill $WeekEmpty $WeekPct $d.weekPct
    $script:lastSessRst = $d.sessionRst
    $script:lastWeekRst = $d.weekRst
    Update-Countdowns
}

function Update-Countdowns {
    if ($script:lastSessRst) { $SessRst.Text = 'reset dans ' + (Format-Countdown $script:lastSessRst) }
    if ($script:lastWeekRst) { $WeekRst.Text = 'reset dans ' + (Format-Countdown $script:lastWeekRst) }
}

# ---------- Timers ----------
$dataTimer = New-Object System.Windows.Threading.DispatcherTimer
$dataTimer.Interval = [TimeSpan]::FromMilliseconds($PollMs)
$dataTimer.Add_Tick({ Refresh-Data })

$tickTimer = New-Object System.Windows.Threading.DispatcherTimer
$tickTimer.Interval = [TimeSpan]::FromSeconds(30)
$tickTimer.Add_Tick({ Update-Countdowns })

$win.Add_SourceInitialized({
    Refresh-Data
    $dataTimer.Start()
    $tickTimer.Start()
})

# Après le 1er rendu : la fenêtre a pris sa taille naturelle -> on fige le ratio,
# on applique la taille mémorisée et on positionne la fenêtre.
$win.Add_ContentRendered({
    if ($script:inited) { return }
    $script:inited = $true
    $win.SizeToContent = 'Manual'
    if ($win.ActualHeight -gt 0) { $script:aspect = $win.ActualWidth / $win.ActualHeight }
    $w = if ($script:savedW) { [double]$script:savedW } else { $win.ActualWidth }
    Resize-To $w
    if ($null -ne $script:savedLeft) {
        $win.Left = [double]$script:savedLeft; $win.Top = [double]$script:savedTop
    } else {
        $wa = [Windows.SystemParameters]::WorkArea
        $win.Left = $wa.Right  - $win.Width  - 12
        $win.Top  = $wa.Bottom - $win.Height - 12
    }
})

[void]$win.ShowDialog()
