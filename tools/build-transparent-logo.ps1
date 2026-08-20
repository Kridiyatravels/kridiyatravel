param(
  [Parameter(Mandatory = $true)][string]$SourcePath,
  [Parameter(Mandatory = $true)][string]$WorkspacePath
)

Add-Type -AssemblyName System.Drawing

function New-TransparentLogo([string]$source, [string]$destination) {
  $inputImage = [System.Drawing.Bitmap]::FromFile($source)
  try {
    $outputImage = New-Object System.Drawing.Bitmap($inputImage.Width, $inputImage.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
      for ($y = 0; $y -lt $inputImage.Height; $y++) {
        for ($x = 0; $x -lt $inputImage.Width; $x++) {
          $pixel = $inputImage.GetPixel($x, $y)
          $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
          $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
          $chroma = $maximum - $minimum
          $alpha = [Math]::Max(0, [Math]::Min(255, [int](($chroma - 3) * 6.1)))
          $outputImage.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $pixel.R, $pixel.G, $pixel.B))
        }
      }
      $outputImage.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $outputImage.Dispose()
    }
  } finally {
    $inputImage.Dispose()
  }
}

function Save-ResizedLogo([string]$source, [string]$destination, [int]$width, [int]$height) {
  $inputImage = [System.Drawing.Bitmap]::FromFile($source)
  try {
    $outputImage = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
      $graphics = [System.Drawing.Graphics]::FromImage($outputImage)
      try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($inputImage, 0, 0, $width, $height)
      } finally {
        $graphics.Dispose()
      }
      $outputImage.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
      $outputImage.Dispose()
    }
  } finally {
    $inputImage.Dispose()
  }
}

$assetRoot = Join-Path $WorkspacePath 'assets'
$masterPath = Join-Path $assetRoot 'brand\kridiya-logo-transparent.png'
New-TransparentLogo $SourcePath $masterPath

$fullSizeTargets = @(
  (Join-Path $assetRoot 'brand\kridiya-logo-hd.png'),
  (Join-Path $assetRoot 'brand\kridiya-logo-hd-white.png'),
  (Join-Path $assetRoot 'email-signature\kridiya-signature-logo-transparent.png'),
  (Join-Path $assetRoot 'email-signature\kridiya-signature-logo.png')
)
foreach ($target in $fullSizeTargets) { Copy-Item -LiteralPath $masterPath -Destination $target -Force }

Save-ResizedLogo $masterPath (Join-Path $assetRoot 'logo.png') 256 256
Save-ResizedLogo $masterPath (Join-Path $assetRoot 'banners\linkedin\kridiya-logo.png') 256 256
Save-ResizedLogo $masterPath (Join-Path $assetRoot 'favicon-180.png') 180 180
Save-ResizedLogo $masterPath (Join-Path $assetRoot 'favicon-32.png') 32 32
