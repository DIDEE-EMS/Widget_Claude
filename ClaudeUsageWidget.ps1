# ============================================================
#  Claude Usage Widget  -  bureau Windows 11
#  Affiche la conso Session (5h) + Hebdo (7j) + reset
#  Lance avec : powershell -ExecutionPolicy Bypass -File ClaudeUsageWidget.ps1
#  (ou via ClaudeWidget.vbs pour un lancement silencieux)
# ============================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ---------- Config ----------
if ($MyInvocation.MyCommand.Path) { $ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
else { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$CredPath   = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$PosPath    = Join-Path $ScriptDir 'widget_pos.json'
$ClientId   = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Hotkey {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
}
"@

function Write-Log($msg) {
    try {
        $file = Join-Path $ScriptDir "ClaudeHistory.log"
        "[{0:yyyy-MM-dd HH:mm:ss}] $msg" -f (Get-Date) | Out-File -FilePath $file -Append -Encoding UTF8
    } catch {}
}
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
    if ($span.TotalDays   -ge 1) { return ('{0}j {1}h'   -f [Math]::Floor($span.TotalDays), $span.Hours) }
    if ($span.TotalHours  -ge 1) { return ('{0}h {1}min' -f [Math]::Floor($span.TotalHours), $span.Minutes) }
    return ('{0} min' -f [Math]::Round($span.TotalMinutes))
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
    <Border x:Name="MainBorder" Width="280" Background="#EE1B1B1F" CornerRadius="14" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="14">
      <Border.ContextMenu>
        <ContextMenu>
          <MenuItem x:Name="MiAlwaysOnTop" Header="Toujours au-dessus" IsCheckable="True" IsChecked="True"/>
          <MenuItem x:Name="MiGhost" Header="Mode Fantôme (Transparent)" IsCheckable="True" IsChecked="False"/>
          <MenuItem Header="Thème">
            <MenuItem x:Name="MiThemeNormal" Header="Défaut" IsCheckable="True" IsChecked="True"/>
            <MenuItem x:Name="MiThemeRainbow" Header="Rainbow" IsCheckable="True" IsChecked="False"/>
            <MenuItem x:Name="MiThemeN64" Header="Nintendo 64" IsCheckable="True" IsChecked="False"/>
            <MenuItem x:Name="MiThemeGC" Header="Gamecube" IsCheckable="True" IsChecked="False"/>
            <MenuItem x:Name="MiThemeDJ" Header="DJ" IsCheckable="True" IsChecked="False"/>
            <MenuItem x:Name="MiTheme888" Header="888" IsCheckable="True" IsChecked="False"/>
          </MenuItem>
          <MenuItem x:Name="MiSound" Header="Activer le son des tokens" IsCheckable="True" IsChecked="True"/>
          <MenuItem x:Name="MiToast" Header="Activer les notifications Windows" IsCheckable="True" IsChecked="True"/>
          <Separator/>
          <MenuItem x:Name="MiAbout" Header="À propos..."/>
        </ContextMenu>
      </Border.ContextMenu>
    <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.5"/></Border.Effect>
    <StackPanel>
      <Grid>
        <StackPanel Orientation="Horizontal">
          <Ellipse Width="9" Height="9" Fill="#D97757" VerticalAlignment="Center"/>
          <TextBlock Text="Claude" Foreground="#FFFFFF" FontFamily="Segoe UI" FontSize="13"
                     FontWeight="SemiBold" Margin="7,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="v1.3" Foreground="#666666" FontFamily="Segoe UI" FontSize="10"
                     FontWeight="Regular" Margin="6,2,0,0" VerticalAlignment="Center"/>
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
      <Grid Margin="0,0,0,0" Height="24">
        <Image x:Name="PikaImg" Stretch="Uniform" Width="24" Height="24" HorizontalAlignment="Left" Margin="0,0,0,0"/>
        <TextBlock x:Name="DjText" Text="( &#x0E4F; )( &#x0E4F; )" Visibility="Collapsed"
                   Foreground="#FF2D95" FontFamily="Segoe UI, Leelawadee UI, Nirmala UI" FontSize="15"
                   FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="0,0,0,0">
          <TextBlock.RenderTransform>
            <TranslateTransform x:Name="DjShift" X="0"/>
          </TextBlock.RenderTransform>
        </TextBlock>
        <TextBlock x:Name="DjBoing" Text="Boing Boing" Visibility="Collapsed"
                   Foreground="#CCFF8FC7" FontFamily="Segoe UI" FontSize="8" FontStyle="Italic"
                   FontWeight="SemiBold" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="0,0,0,0">
          <TextBlock.RenderTransform>
            <TranslateTransform x:Name="DjBoingShift" Y="0"/>
          </TextBlock.RenderTransform>
        </TextBlock>
        <TextBlock x:Name="EightText" Text="8=D" Visibility="Collapsed"
                   Foreground="#8A8F9A" FontFamily="Consolas, Segoe UI" FontSize="15"
                   FontWeight="Bold" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="0,0,0,0"/>
      </Grid>
      <Border Background="#3C3C48" CornerRadius="6" Height="12" Margin="0,2,0,0" ClipToBounds="True">
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
$PikaImg  = $win.FindName('PikaImg')
$DjText   = $win.FindName('DjText')
$DjShift  = $win.FindName('DjShift')
$DjBoing  = $win.FindName('DjBoing')
$DjBoingShift = $win.FindName('DjBoingShift')
$EightText = $win.FindName('EightText')

# Petit dandinement gauche-droite du DJ (quelques pixels), avec un "Boing Boing" qui rebondit
$script:djPhase = 0.0
$script:djTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:djTimer.Interval = [TimeSpan]::FromMilliseconds(60)
$script:djTimer.Add_Tick({
    $script:djPhase += 0.35
    $s = [Math]::Sin($script:djPhase)
    $DjShift.X = $s * 3.0
    if ($DjBoing) {
        # rebond vertical synchro : le texte saute quand les parenthèses tapent un bord
        $DjBoingShift.Y = -[Math]::Abs($s) * 4.0
        # suit horizontalement le visage, décalé de quelques pixels
        $DjBoing.Margin = New-Object System.Windows.Thickness ([double]$DjText.Margin.Left + 6), 0, 0, 0
    }
})
try {
    $decoder = New-Object System.Windows.Media.Imaging.GifBitmapDecoder([Uri]::new((Join-Path $ScriptDir 'pikachu-cours-dark.gif')), [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat, [System.Windows.Media.Imaging.BitmapCacheOption]::Default)
    $script:pikaFrames = $decoder.Frames
    if ($script:pikaFrames.Count -gt 0) {
        $PikaImg.Source = $script:pikaFrames[0]
        $script:pikaFrameIdx = 0
        $script:pikaTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:pikaTimer.Interval = [TimeSpan]::FromMilliseconds(50)
        $script:pikaTimer.Add_Tick({
            $script:pikaFrameIdx = ($script:pikaFrameIdx + 1) % $script:pikaFrames.Count
            $PikaImg.Source = $script:pikaFrames[$script:pikaFrameIdx]
        })
        $script:pikaTimer.Start()
    }
} catch {}

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
    $t = 'Normal'
    if ($win.FindName('MiThemeRainbow').IsChecked) { $t = 'Rainbow' }
    if ($win.FindName('MiThemeN64').IsChecked) { $t = 'N64' }
    if ($win.FindName('MiThemeGC').IsChecked) { $t = 'GC' }
    if ($win.FindName('MiThemeDJ').IsChecked) { $t = 'DJ' }
    if ($win.FindName('MiTheme888').IsChecked) { $t = '888' }

    if ($t -eq 'Rainbow') {
        $br = [System.Windows.Media.LinearGradientBrush]::new()
        $br.StartPoint = [System.Windows.Point]::new(0,0); $br.EndPoint = [System.Windows.Point]::new(1,0)
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#4ADE80'), 0.0))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FBBF24'), 0.5))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#F87171'), 1.0))
        $bar.Background = $br
    } elseif ($t -eq 'N64') {
        $br = [System.Windows.Media.LinearGradientBrush]::new()
        $br.StartPoint = [System.Windows.Point]::new(0,0); $br.EndPoint = [System.Windows.Point]::new(1,0)
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#0072CE'), 0.0))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#00A651'), 0.33))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FFCC00'), 0.66))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#E41A28'), 1.0))
        $bar.Background = $br
    } elseif ($t -eq 'GC') {
        $br = [System.Windows.Media.LinearGradientBrush]::new()
        $br.StartPoint = [System.Windows.Point]::new(0,0); $br.EndPoint = [System.Windows.Point]::new(1,0)
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#4B0082'), 0.0))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#808080'), 0.5))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FFA500'), 1.0))
        $bar.Background = $br
    } elseif ($t -eq 'DJ') {
        # Rose Playboy
        $br = [System.Windows.Media.LinearGradientBrush]::new()
        $br.StartPoint = [System.Windows.Point]::new(0,0); $br.EndPoint = [System.Windows.Point]::new(1,0)
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FF8FC7'), 0.0))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FF2D95'), 0.5))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#E6007E'), 1.0))
        $bar.Background = $br
    } elseif ($t -eq '888') {
        # Palette maussade / triste : gris-bleu délavés
        $br = [System.Windows.Media.LinearGradientBrush]::new()
        $br.StartPoint = [System.Windows.Point]::new(0,0); $br.EndPoint = [System.Windows.Point]::new(1,0)
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#3A3F4B'), 0.0))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#4A5060'), 0.5))
        $br.GradientStops.Add([System.Windows.Media.GradientStop]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#5A6070'), 1.0))
        $bar.Background = $br
    } else {
        $c = Get-BarColor $pct
        $bar.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString($c) ))
    }
    if ($pctBox.Name -eq 'SessPct') {
        if ($t -eq 'DJ') {
            if ($PikaImg) { $PikaImg.Visibility = 'Collapsed' }
            if ($EightText) { $EightText.Visibility = 'Collapsed' }
            if ($DjText) {
                $DjText.Visibility = 'Visible'
                $w = if ($DjText.ActualWidth -gt 0) { $DjText.ActualWidth } else { 62 }
                $usable = [Math]::Max(0, 252 - $w)
                $left = ($pct / 100) * $usable
                $DjText.Margin = New-Object System.Windows.Thickness $left, 0, 0, 0
            }
            if ($DjBoing) { $DjBoing.Visibility = 'Visible' }
        } elseif ($t -eq '888') {
            if ($PikaImg) { $PikaImg.Visibility = 'Collapsed' }
            if ($DjText) { $DjText.Visibility = 'Collapsed' }
            if ($DjBoing) { $DjBoing.Visibility = 'Collapsed' }
            if ($EightText) {
                # un "=" de plus par tranche de 10 % :  8=D, 8==D, 8===D ...
                $n = [Math]::Max(1, [int][Math]::Ceiling([Math]::Round($pct) / 10.0))
                $EightText.Text = '8' + ('=' * $n) + 'D'
                $EightText.Visibility = 'Visible'
            }
        } else {
            if ($DjText) { $DjText.Visibility = 'Collapsed' }
            if ($DjBoing) { $DjBoing.Visibility = 'Collapsed' }
            if ($EightText) { $EightText.Visibility = 'Collapsed' }
            if ($PikaImg) {
                $PikaImg.Visibility = 'Visible'
                $usable = 252 - 24
                $left = ($pct / 100) * $usable
                $PikaImg.Margin = New-Object System.Windows.Thickness $left, 0, 0, 0
            }
        }
    }
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
    $play = $false
    if ($script:hasData -and $script:lastSessRst -and $d.sessionRst -and ($script:lastSessRst -ne $d.sessionRst)) {
        try {
            $oldTime = ([datetimeoffset]$script:lastSessRst).LocalDateTime
            if ((Get-Date) -ge $oldTime.AddMinutes(-5)) { $play = $true }
        } catch {}
    }
    if ($script:hasData -and ($null -ne $script:lastSessPct) -and (($script:lastSessPct - $d.sessionPct) -ge 1)) {
        $play = $true
    }
    if ($script:hasData) {
        if ($d.sessionPct -ge 95 -and $script:lastSessPct -lt 95) { Write-Log "Limite Claude presque atteinte ($($d.sessionPct)%)." }
        if ($d.sessionPct -eq 100 -and $script:lastSessPct -lt 100) { Write-Log "Limite Claude atteinte (100%)." }
    }
    if ($play) {
        Write-Log "Crédits restaurés. Utilisation redescendue de $($script:lastSessPct)% à $($d.sessionPct)%."
        if ($win.FindName('MiSound').IsChecked) {
            try { (New-Object System.Media.SoundPlayer "C:\Windows\Media\tada.wav").Play() } catch {}
        }
        if ($win.FindName('MiToast').IsChecked) {
            try {
                if (-not $script:toastIcon) {
                    $script:toastIcon = New-Object System.Windows.Forms.NotifyIcon
                    $script:toastIcon.Icon = [System.Drawing.SystemIcons]::Information
                    $script:toastIcon.Visible = $true
                }
                $script:toastIcon.ShowBalloonTip(5000, "Claude Widget", "Vos crédits Claude sont de retour !", [System.Windows.Forms.ToolTipIcon]::Info)
            } catch {}
        }
    }
    $script:hasData = $true
    Update-Bar $SessBar $SessFill $SessEmpty $SessPct $d.sessionPct
    Update-Bar $WeekBar $WeekFill $WeekEmpty $WeekPct $d.weekPct
    $script:lastSessPct = $d.sessionPct
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
$tickTimer.Add_Tick({ 
    Update-Countdowns
    if ($win.FindName('MiAlwaysOnTop').IsChecked) { $win.Topmost = $true }
})

$win.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        $src = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $src.AddHook({
            param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
            if ($msg -eq 0x0312 -and $wParam -eq 1) {
                if ($win.Visibility -eq 'Visible') { $win.Visibility = 'Hidden' }
                else { 
                    $win.Visibility = 'Visible'
                    if ($win.FindName('MiAlwaysOnTop').IsChecked) { $win.Topmost = $true }
                    $win.Activate()
                }
                $handled = $true
            }
            return [IntPtr]::Zero
        })
        [Hotkey]::RegisterHotKey($hwnd, 1, 6, 0x43)
    } catch {}
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

$win.FindName('MiAlwaysOnTop').Add_Click({ $win.Topmost = $win.FindName('MiAlwaysOnTop').IsChecked })
$win.FindName('MiGhost').Add_Click({ if ($win.FindName('MiGhost').IsChecked) { $win.Opacity = 0.5 } else { $win.Opacity = 1.0 } })

function Set-Theme($t) {
    $win.FindName('MiThemeNormal').IsChecked = ($t -eq 'Normal')
    $win.FindName('MiThemeRainbow').IsChecked = ($t -eq 'Rainbow')
    $win.FindName('MiThemeN64').IsChecked = ($t -eq 'N64')
    $win.FindName('MiThemeGC').IsChecked = ($t -eq 'GC')
    $win.FindName('MiThemeDJ').IsChecked = ($t -eq 'DJ')
    $win.FindName('MiTheme888').IsChecked = ($t -eq '888')

    $mb = $win.FindName('MainBorder')
    if ($t -eq 'GC') {
        $mb.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString('#EE1A1A24') ))
    } elseif ($t -eq 'N64') {
        $mb.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString('#EE2A2A2A') ))
    } elseif ($t -eq 'DJ') {
        $mb.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString('#EE2A0E1E') ))
    } elseif ($t -eq '888') {
        $mb.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString('#EE16181D') ))
    } else {
        $mb.Background = [System.Windows.Media.SolidColorBrush]::new(( [System.Windows.Media.ColorConverter]::ConvertFromString('#EE1B1B1F') ))
    }

    # Dandinement du DJ : actif uniquement sur ce thème
    if ($t -eq 'DJ') { $script:djTimer.Start() }
    else { $script:djTimer.Stop(); if ($DjShift) { $DjShift.X = 0 }; if ($DjBoingShift) { $DjBoingShift.Y = 0 } }

    Refresh-Data
}

$win.FindName('MiThemeNormal').Add_Click({ Set-Theme 'Normal' })
$win.FindName('MiThemeRainbow').Add_Click({ Set-Theme 'Rainbow' })
$win.FindName('MiThemeN64').Add_Click({ Set-Theme 'N64' })
$win.FindName('MiThemeGC').Add_Click({ Set-Theme 'GC' })
$win.FindName('MiThemeDJ').Add_Click({ Set-Theme 'DJ' })
$win.FindName('MiTheme888').Add_Click({ Set-Theme '888' })

$win.FindName('MiAbout').Add_Click({
    $ab = New-Object System.Windows.Forms.Form
    $ab.Text = 'À propos'
    $ab.Size = New-Object System.Drawing.Size 320, 360
    $ab.StartPosition = 'CenterScreen'
    $ab.FormBorderStyle = 'FixedDialog'
    $ab.MaximizeBox = $false
    $al = New-Object System.Windows.Forms.Label
    $al.Text = 'Made In DIDEE EMS 2026'
    $al.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $al.Location = New-Object System.Drawing.Point 10, 10
    $al.AutoSize = $true
    $ab.Controls.Add($al)
    $pb = New-Object System.Windows.Forms.PictureBox
    $pb.Location = New-Object System.Drawing.Point 10, 45
    $pb.Size = New-Object System.Drawing.Size 280, 260
    $pb.SizeMode = 'Zoom'
    $pb.ImageLocation = 'https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif'
    $ab.Controls.Add($pb)
    $ab.ShowDialog()
})

[void]$win.ShowDialog()
