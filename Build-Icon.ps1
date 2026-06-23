# Génère claude.ico (icône du widget : fond sombre + 2 barres) en plusieurs tailles.
Add-Type -AssemblyName System.Drawing

function New-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # fond arrondi
    $inset = [Math]::Max(1, $s * 0.05)
    $rad   = $s * 0.22
    $rect  = New-Object System.Drawing.RectangleF $inset, $inset, ($s - 2*$inset), ($s - 2*$inset)
    $path  = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,27,27,31))
    $g.FillPath($bg, $path); $bg.Dispose()

    # 2 barres
    $bx = $s * 0.22; $bw = $s * 0.56; $bh = [Math]::Max(2, $s * 0.13); $bradius = $bh/2
    function Bar([single]$y, [double]$frac, [System.Drawing.Color]$col) {
        $tr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70,255,255,255))
        $g.FillRectangle($tr, $bx, $y, $bw, $bh); $tr.Dispose()
        $fb = New-Object System.Drawing.SolidBrush $col
        $g.FillRectangle($fb, $bx, $y, [single]($bw*$frac), $bh); $fb.Dispose()
    }
    Bar ([single]($s*0.34)) 0.72 ([System.Drawing.Color]::FromArgb(255,251,191,36))  # ambre
    Bar ([single]($s*0.56)) 0.32 ([System.Drawing.Color]::FromArgb(255,74,222,128))  # vert
    $g.Dispose()
    return $bmp
}

$sizes = 16,24,32,48,64,128,256
$pngs = foreach ($sz in $sizes) {
    $bmp = New-IconBitmap $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    ,($ms.ToArray())
}

# Assemblage du fichier .ico (entrées PNG)
$out = New-Object System.IO.MemoryStream
$bw  = New-Object System.IO.BinaryWriter $out
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)   # header
$offset = 6 + 16*$sizes.Count
for ($i=0; $i -lt $sizes.Count; $i++) {
    $sz = $sizes[$i]; $data = $pngs[$i]
    $bw.Write([byte]($(if ($sz -ge 256) {0} else {$sz})))   # width
    $bw.Write([byte]($(if ($sz -ge 256) {0} else {$sz})))   # height
    $bw.Write([byte]0); $bw.Write([byte]0)                  # colors, reserved
    $bw.Write([uint16]1); $bw.Write([uint16]32)             # planes, bpp
    $bw.Write([uint32]$data.Length)                         # size
    $bw.Write([uint32]$offset)                              # offset
    $offset += $data.Length
}
foreach ($data in $pngs) { $bw.Write($data) }
$bw.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'claude.ico'), $out.ToArray())
$bw.Dispose()
"claude.ico créé ($($sizes.Count) tailles)"
