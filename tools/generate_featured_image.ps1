Add-Type -AssemblyName System.Drawing

# Output size: 1200x630 is the Open Graph / Twitter card standard. Works
# for app store featured banners, social media cards, GitHub repo social
# preview, and most README hero images.
$W = 1200
$H = 630

# Brand colors (same as the launcher icon).
$bgTop    = [System.Drawing.Color]::FromArgb(255, 149, 117, 255)   # #9575FF
$bgMid    = [System.Drawing.Color]::FromArgb(255, 124,  88, 248)   # mid
$bgBot    = [System.Drawing.Color]::FromArgb(255,  91,  47, 224)   # #5B2FE0
$accent   = [System.Drawing.Color]::FromArgb(255, 255, 200,  87)   # #FFC857
$white    = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$muted    = [System.Drawing.Color]::FromArgb(220, 245, 240, 255)   # 87% white

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# Background: diagonal gradient from top-left to bottom-right.
$bgRect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
$bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF 0, 0),
    (New-Object System.Drawing.PointF $W, $H),
    $bgTop, $bgBot)
$bgBrush.InterpolationColors = New-Object System.Drawing.Drawing2D.ColorBlend(
    (,[float[]]@(0.0, 0.55, 1.0)),
    (,[System.Drawing.Color[]]@($bgTop, $bgMid, $bgBot)))
$g.FillRectangle($bgBrush, $bgRect)
$bgBrush.Dispose()

# Soft white halo behind the bell for depth.
$halo = New-Object System.Drawing.Drawing2D.GraphicsPath
$halo.AddEllipse(60, 50, 480, 480)
$haloBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(36, 255, 255, 255))
$g.FillPath($haloBrush, $halo)

# Bell mark on the left, scaled up from the launcher icon. The
# coordinates are 2x the icon's source to keep proportions.
$cx = 300
$cy = 315
$s  = 2.4

# Drop shadow.
$shadow = New-Object System.Drawing.Drawing2D.GraphicsPath
$shadow.AddEllipse( [int]($cx - 144 * $s / 2.4), [int]($cy + 88 * $s / 2.4), 288, 34)
$shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(72, 0, 0, 0))
$g.FillPath($shadowBrush, $shadow)

# Bell silhouette.
$bell = New-Object System.Drawing.Drawing2D.GraphicsPath
$bell.StartFigure()
$bell.AddLine( [int]($cx - 60 * $s), [int]($cy - 80 * $s),
              [int]($cx + 60 * $s), [int]($cy - 80 * $s))
$bell.AddLine( [int]($cx + 60 * $s), [int]($cy - 80 * $s),
              [int]($cx + 88 * $s), [int]($cy + 40 * $s))
$bell.AddBezier(
    [float]($cx + 88 * $s), [float]($cy + 40 * $s),
    [float]($cx + 88 * $s), [float]($cy + 100 * $s),
    [float]($cx - 88 * $s), [float]($cy + 100 * $s),
    [float]($cx - 88 * $s), [float]($cy + 40 * $s))
$bell.AddLine( [int]($cx - 88 * $s), [int]($cy + 40 * $s),
              [int]($cx - 60 * $s), [int]($cy - 80 * $s))
$bell.CloseFigure()
$g.FillPath((New-Object System.Drawing.SolidBrush $white), $bell)

# Clapper.
$g.FillEllipse((New-Object System.Drawing.SolidBrush $white), [int]($cx - 10 * $s), [int]($cy + 96 * $s), 48, 48)

# Lightning accent.
$bolt = New-Object System.Drawing.Drawing2D.GraphicsPath
$bolt.StartFigure()
$bolt.AddLine( [int]($cx + 32 * $s), [int]($cy - 16 * $s),
              [int]($cx - 8  * $s), [int]($cy + 12 * $s))
$bolt.AddLine( [int]($cx - 8  * $s), [int]($cy + 12 * $s),
              [int]($cx + 12 * $s), [int]($cy - 2  * $s))
$bolt.AddLine( [int]($cx + 12 * $s), [int]($cy - 2  * $s),
              [int]($cx - 28 * $s), [int]($cy + 56 * $s))
$bolt.AddLine( [int]($cx - 28 * $s), [int]($cy + 56 * $s),
              [int]($cx - 4  * $s), [int]($cy + 32 * $s))
$bolt.AddLine( [int]($cx - 4  * $s), [int]($cy + 32 * $s),
              [int]($cx - 24 * $s), [int]($cy + 44 * $s))
$bolt.CloseFigure()
$g.FillPath((New-Object System.Drawing.SolidBrush $accent), $bolt)

# Notification dot at the top-right of the bell.
$g.FillEllipse((New-Object System.Drawing.SolidBrush $accent), [int]($cx + 56 * $s), [int]($cy - 100 * $s), 86, 86)

# Right side: the wordmark and tagline.
# Pick a heavy sans font. Fall back to a default if the named one is
# missing (PowerShell's GDI+ resolves the fallback automatically).
$nameFontFamily = 'Segoe UI'
try { $nameFont = New-Object System.Drawing.Font($nameFontFamily, 132, [System.Drawing.FontStyle]::Bold) }
catch { $nameFont = New-Object System.Drawing.Font('Arial', 132, [System.Drawing.FontStyle]::Bold) }
$taglineFont = New-Object System.Drawing.Font($nameFontFamily, 30, [System.Drawing.FontStyle]::Regular)
$badgeFont   = New-Object System.Drawing.Font($nameFontFamily, 22, [System.Drawing.FontStyle]::Bold)

# Wordmark: "NUDGE"
$g.DrawString('NUDGE', $nameFont, (New-Object System.Drawing.SolidBrush $white), 600, 215)

# Tagline.
$tagline = 'Context-aware reminders for Android'
$g.DrawString($tagline, $taglineFont, (New-Object System.Drawing.SolidBrush $muted), 600, 380)

# Small "1.0" badge under the tagline.
$badgeRect = New-Object System.Drawing.Rectangle 600, 445, 96, 36
$g.FillRectangle((New-Object System.Drawing.SolidBrush $accent), $badgeRect)
$g.DrawString('1.0', $badgeFont, (New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 36, 12, 84))), 600, 451)
# "Now on Uptodown" right after the badge.
$g.DrawString('Now on Uptodown', $badgeFont, (New-Object System.Drawing.SolidBrush $muted), 712, 451)

$nameFont.Dispose()
$taglineFont.Dispose()
$badgeFont.Dispose()
$g.Dispose()

$outDir = 'C:\Users\Vendex\Documents\nudge-uptodown-upload'
$outPath = Join-Path $outDir 'featured.png'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ('Wrote ' + $outPath + ' (' + $W + 'x' + $H + ')')