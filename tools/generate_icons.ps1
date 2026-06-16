Add-Type -AssemblyName System.Drawing

# Brand colors
$bgTop = [System.Drawing.Color]::FromArgb(255, 149, 117, 255)     # #9575FF
$bgBot = [System.Drawing.Color]::FromArgb(255, 91, 47, 224)      # #5B2FE0
$fg = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$accent = [System.Drawing.Color]::FromArgb(255, 255, 200, 87)    # #FFC857

# Sizes
$BG_SIZE = 432
$FG_SIZE = 432

# Background: 432x432 PNG with a subtle vertical gradient.
$bgBmp = New-Object System.Drawing.Bitmap $BG_SIZE, $BG_SIZE
$bgG = [System.Drawing.Graphics]::FromImage($bgBmp)
$bgG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$rect = New-Object System.Drawing.Rectangle 0, 0, $BG_SIZE, $BG_SIZE
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF 0, 0),
    (New-Object System.Drawing.PointF 0, $BG_SIZE),
    $bgTop, $bgBot)
$bgG.FillRectangle($brush, $rect)
# Soft circle highlight at the top to give the disc a subtle 3D feel.
$highlight = New-Object System.Drawing.Drawing2D.GraphicsPath
$highlight.AddEllipse(-120, -180, 480, 360)
$hlBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 255, 255, 255))
$bgG.FillPath($hlBrush, $highlight)
$bgG.Dispose()
$bgDir = Join-Path $PSScriptRoot '..\assets\icon'
$bgPath = Join-Path $bgDir 'app_icon_background.png'
$bgBmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bgBmp.Dispose()
Write-Output ('Wrote ' + $bgPath)

# Foreground: 432x432 PNG with a white bell mark centered in the safe zone.
# Safe zone for adaptive icons is the central 66dp of the 108dp canvas.
# At xxxhdpi (4x) that is 264x264 inside the 432x432 canvas, centered.
$fgBmp = New-Object System.Drawing.Bitmap $FG_SIZE, $FG_SIZE
$fgG = [System.Drawing.Graphics]::FromImage($fgBmp)
$fgG.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$fgG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$fgG.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$cx = 216
$cy = 216
$s = 1.0  # scale

# Drop shadow under the bell to give it depth on the gradient.
$shadow = New-Object System.Drawing.Drawing2D.GraphicsPath
$shadow.AddEllipse( [int]($cx - 60 * $s), [int]($cy + 88 * $s), 120, 14)
$shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
$fgG.FillPath($shadowBrush, $shadow)

# Bell body: a stylized "bell" silhouette drawn from a closed path
# using straight lines for the sides and a single cubic Bezier for
# the rounded bottom.
$bell = New-Object System.Drawing.Drawing2D.GraphicsPath
$bell.StartFigure()
# Top: a flat-top trapezoidal cap.
$bell.AddLine( [int]($cx - 60 * $s), [int]($cy - 80 * $s),
              [int]($cx + 60 * $s), [int]($cy - 80 * $s))
# Right side flares slightly outward going down.
$bell.AddLine( [int]($cx + 60 * $s), [int]($cy - 80 * $s),
              [int]($cx + 88 * $s), [int]($cy + 40 * $s))
# Rounded bottom: single cubic Bezier from the right side end to the
# left side end, sweeping down through the bottom of the bell.
$bell.AddBezier(
    [float]($cx + 88 * $s), [float]($cy + 40 * $s),
    [float]($cx + 88 * $s), [float]($cy + 100 * $s),
    [float]($cx - 88 * $s), [float]($cy + 100 * $s),
    [float]($cx - 88 * $s), [float]($cy + 40 * $s))
# Left side goes back up to the top.
$bell.AddLine( [int]($cx - 88 * $s), [int]($cy + 40 * $s),
              [int]($cx - 60 * $s), [int]($cy - 80 * $s))
$bell.CloseFigure()

# Fill the bell in solid white.
$bellBrush = New-Object System.Drawing.SolidBrush $fg
$fgG.FillPath($bellBrush, $bell)

# Clapper: a small white dot at the very bottom of the bell.
$clapper = New-Object System.Drawing.SolidBrush $fg
$fgG.FillEllipse($clapper, [int]($cx - 10 * $s), [int]($cy + 96 * $s), 20, 20)

# Small lightning-bolt accent in the lower-right of the bell body.
# Suggests "context-aware" (the trigger that fires the nudge).
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
$boltBrush = New-Object System.Drawing.SolidBrush $accent
$fgG.FillPath($boltBrush, $bolt)

# Notification dot at the top-right of the bell.
$dotBrush = New-Object System.Drawing.SolidBrush $accent
$fgG.FillEllipse($dotBrush, [int]($cx + 56 * $s), [int]($cy - 100 * $s), 36, 36)

$fgG.Dispose()
$fgPath = Join-Path $bgDir 'app_icon_foreground.png'
$fgBmp.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$fgBmp.Dispose()
Write-Output ('Wrote ' + $fgPath)