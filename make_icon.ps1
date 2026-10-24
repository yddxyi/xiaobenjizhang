# App icon generator (ASCII-only on purpose: PowerShell 5.1 misreads
# UTF-8 Chinese comments as GBK and can break parsing; keep this file ASCII).
# Produces a blue gradient (#43B6E4 -> deeper blue) icon with a white yen sign.

Add-Type -AssemblyName System.Drawing
$size = 1024
$dir = "E:\Desktop\xbjz\XiaoBenJiZhang\Resources\Assets.xcassets\AppIcon.appiconset"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

# Theme color #43B6E4 -> deeper blue, diagonal gradient.
# NOTE: use the 3-arg FromArgb; the 4-arg overload fails to bind in PowerShell.
$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(67, 182, 228),
    [System.Drawing.Color]::FromArgb(20, 120, 190),
    45.0)
$g.FillRectangle($brush, $rect)

$font = New-Object System.Drawing.Font("Microsoft YaHei", [single]480, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$rectF = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
$g.DrawString([string][char]0xA5, $font, [System.Drawing.Brushes]::White, $rectF, $fmt)

$g.Dispose()
$bmp.Save("$dir\AppIcon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "icon saved: $dir\AppIcon.png"
