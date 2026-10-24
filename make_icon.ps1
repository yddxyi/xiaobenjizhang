Add-Type -AssemblyName System.Drawing
$size = 1024
$dir = "E:\Desktop\xbjz\XiaoBenJiZhang\Resources\Assets.xcassets\AppIcon.appiconset"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# 先用普通构造建图，画完后整体不透明即可
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

# 暖橙 -> 珊瑚红对角渐变，与 App 内本周卡片同一配色
$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(255, 122, 26),
    [System.Drawing.Color]::FromArgb(255, 82, 92),
    45.0)
$g.FillRectangle($brush, $rect)

# 中央白色人民币符号（用字符码构造，避免脚本编码问题；矩形用浮点版 RectangleF）
$rectF = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
$font = New-Object System.Drawing.Font("Microsoft YaHei", [single]480, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$yen = [string][char]0xA5
$g.DrawString($yen, $font, [System.Drawing.Brushes]::White, $rectF, $fmt)

$g.Dispose()
$bmp.Save("$dir\AppIcon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "icon saved: $dir\AppIcon.png"
