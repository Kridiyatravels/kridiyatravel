param(
    [Parameter(Mandatory = $true)]
    [string] $AssetDirectory
)

Add-Type -AssemblyName System.Drawing

$imageSource = @'
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

public static class FullColourResizer
{
    public static void Resize(string inputPath, string outputPath, bool preserveAlpha)
    {
        using (var source = new Bitmap(inputPath))
        using (var output = new Bitmap(1600, 700, PixelFormat.Format32bppArgb))
        {
            output.SetResolution(96, 96);
            using (var graphics = Graphics.FromImage(output))
            {
                graphics.CompositingMode = preserveAlpha
                    ? CompositingMode.SourceCopy
                    : CompositingMode.SourceOver;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                graphics.Clear(preserveAlpha ? Color.Transparent : Color.White);
                graphics.DrawImage(source, new Rectangle(0, 0, 1600, 700));
            }

            output.Save(outputPath, ImageFormat.Png);
        }
    }

    public static void ExtractLightBackground(string imagePath)
    {
        using (var image = new Bitmap(imagePath))
        {
            int width = image.Width;
            int height = image.Height;
            bool[] visited = new bool[width * height];
            var queue = new Queue<int>();

            for (int x = 0; x < width; x++)
            {
                EnqueueIfBackground(image, x, 0, width, visited, queue);
                EnqueueIfBackground(image, x, height - 1, width, visited, queue);
            }
            for (int y = 0; y < height; y++)
            {
                EnqueueIfBackground(image, 0, y, width, visited, queue);
                EnqueueIfBackground(image, width - 1, y, width, visited, queue);
            }

            while (queue.Count > 0)
            {
                int index = queue.Dequeue();
                int x = index % width;
                int y = index / width;
                Color pixel = image.GetPixel(x, y);
                image.SetPixel(x, y, Color.FromArgb(0, pixel.R, pixel.G, pixel.B));

                EnqueueIfBackground(image, x - 1, y, width, visited, queue);
                EnqueueIfBackground(image, x + 1, y, width, visited, queue);
                EnqueueIfBackground(image, x, y - 1, width, visited, queue);
                EnqueueIfBackground(image, x, y + 1, width, visited, queue);
            }

            string temporaryPath = imagePath + ".transparent.png";
            image.Save(temporaryPath, ImageFormat.Png);
            image.Dispose();
            System.IO.File.Delete(imagePath);
            System.IO.File.Move(temporaryPath, imagePath);
        }
    }

    private static void EnqueueIfBackground(
        Bitmap image,
        int x,
        int y,
        int width,
        bool[] visited,
        Queue<int> queue
    )
    {
        if (x < 0 || y < 0 || x >= image.Width || y >= image.Height) return;
        int index = y * width + x;
        if (visited[index]) return;
        visited[index] = true;

        Color pixel = image.GetPixel(x, y);
        int min = System.Math.Min(pixel.R, System.Math.Min(pixel.G, pixel.B));
        int max = System.Math.Max(pixel.R, System.Math.Max(pixel.G, pixel.B));
        if (min >= 220 && max - min <= 28)
        {
            queue.Enqueue(index);
        }
    }
}
'@

Add-Type -TypeDefinition $imageSource -ReferencedAssemblies System.Drawing

Get-ChildItem -LiteralPath $AssetDirectory -Filter '*.png' |
    Sort-Object Name |
    ForEach-Object {
        $preserveAlpha = $_.Name -like '01-*' -or $_.Name -like '02-*'
        $temporaryPath = Join-Path $AssetDirectory ($_.BaseName + '-resized.png')
        [FullColourResizer]::Resize($_.FullName, $temporaryPath, $preserveAlpha)
        Move-Item -LiteralPath $temporaryPath -Destination $_.FullName -Force
        if ($preserveAlpha) {
            [FullColourResizer]::ExtractLightBackground($_.FullName)
        }
    }
