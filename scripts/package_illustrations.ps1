param(
    [Parameter(Mandatory = $true)]
    [string] $AssetDirectory
)

Add-Type -AssemblyName System.Drawing

$processorSource = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public static class IllustrationProcessor
{
    public static void Resize(string inputPath, string outputPath, bool removeGreen)
    {
        using (var source = new Bitmap(inputPath))
        using (var resized = new Bitmap(1600, 700, PixelFormat.Format32bppArgb))
        {
            resized.SetResolution(96, 96);
            using (var graphics = Graphics.FromImage(resized))
            {
                graphics.CompositingMode = removeGreen
                    ? CompositingMode.SourceCopy
                    : CompositingMode.SourceOver;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                graphics.Clear(removeGreen ? Color.Transparent : Color.White);
                graphics.DrawImage(source, new Rectangle(0, 0, 1600, 700));
            }

            if (removeGreen)
            {
                RemoveGreenKey(resized);
            }

            resized.Save(outputPath, ImageFormat.Png);
        }
    }

    public static void DespillFile(string imagePath)
    {
        using (var image = new Bitmap(imagePath))
        {
            for (int y = 0; y < image.Height; y++)
            {
                for (int x = 0; x < image.Width; x++)
                {
                    Color pixel = image.GetPixel(x, y);
                    int channelMax = Math.Max(pixel.R, pixel.B);
                    bool darkGreenSpill =
                        pixel.R < 110 &&
                        pixel.B < 110 &&
                        pixel.G > channelMax + 10;

                    if (pixel.A < 255 || darkGreenSpill)
                    {
                        int green = Math.Min(pixel.G, channelMax);
                        int alpha = pixel.A < 255
                            ? Math.Max(0, (int)Math.Round((pixel.A - 42) / 213.0 * 255.0))
                            : pixel.A;
                        image.SetPixel(x, y, Color.FromArgb(
                            alpha,
                            pixel.R,
                            green,
                            pixel.B
                        ));
                    }
                }
            }

            string temporaryPath = imagePath + ".despill.png";
            image.Save(temporaryPath, ImageFormat.Png);
            image.Dispose();
            System.IO.File.Delete(imagePath);
            System.IO.File.Move(temporaryPath, imagePath);
        }
    }

    private static void RemoveGreenKey(Bitmap image)
    {
        Color key = image.GetPixel(2, 2);

        for (int y = 0; y < image.Height; y++)
        {
            for (int x = 0; x < image.Width; x++)
            {
                Color pixel = image.GetPixel(x, y);
                double distance = Math.Sqrt(
                    Math.Pow(pixel.R - key.R, 2) +
                    Math.Pow(pixel.G - key.G, 2) +
                    Math.Pow(pixel.B - key.B, 2)
                );

                int alpha;
                if (distance <= 18)
                {
                    alpha = 0;
                }
                else if (distance >= 125)
                {
                    alpha = 255;
                }
                else
                {
                    alpha = (int)Math.Round((distance - 18) / 107.0 * 255.0);
                }

                if (alpha < 255)
                {
                    int greenExcess = Math.Max(0, pixel.G - Math.Max(pixel.R, pixel.B));
                    int green = Math.Max(0, pixel.G - greenExcess);
                    image.SetPixel(x, y, Color.FromArgb(alpha, pixel.R, green, pixel.B));
                }
            }
        }
    }
}
'@

Add-Type -TypeDefinition $processorSource -ReferencedAssemblies System.Drawing

$greenSources = @(
    @{
        Input = '01-corporate-travel-desk-source.png'
        Output = '01-corporate-travel-desk.png'
    },
    @{
        Input = '02-employee-flight-booking-source.png'
        Output = '02-employee-flight-booking.png'
    }
)

foreach ($item in $greenSources) {
    $sourcePath = Join-Path $AssetDirectory $item.Input
    $outputPath = Join-Path $AssetDirectory $item.Output
    if (Test-Path -LiteralPath $sourcePath) {
        [IllustrationProcessor]::Resize(
            $sourcePath,
            $outputPath,
            $true
        )
    }
    if (Test-Path -LiteralPath $outputPath) {
        [IllustrationProcessor]::DespillFile($outputPath)
    }
}

Get-ChildItem -LiteralPath $AssetDirectory -Filter '*.png' |
    Where-Object { $_.Name -notlike '*-source.png' -and $_.Name -notin @(
        '01-corporate-travel-desk.png',
        '02-employee-flight-booking.png'
    ) } |
    ForEach-Object {
        $temporaryPath = Join-Path $AssetDirectory ($_.BaseName + '-resized.png')
        [IllustrationProcessor]::Resize($_.FullName, $temporaryPath, $false)
        Move-Item -LiteralPath $temporaryPath -Destination $_.FullName -Force
    }

foreach ($item in $greenSources) {
    $sourcePath = Join-Path $AssetDirectory $item.Input
    if (Test-Path -LiteralPath $sourcePath) {
        Remove-Item -LiteralPath $sourcePath
    }
}
