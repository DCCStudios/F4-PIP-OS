# Prepares embedded assets for the M1 mockup:
#  - bg.jpg          : 1600x900 cover-cropped in-game scene (blur applied in CSS)
#  - soldier_front.png / soldier_back.png : grey studio backdrop removed (alpha), cropped, scaled
# Output: Previews\assets\ plus .b64.txt siblings for template injection.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$src = @{
  bg    = "C:\Users\rober\Pictures\Screenshots\Screenshot 2026-08-15 061701.png"
  front = "C:\Users\rober\Pictures\Screenshots\Screenshot 2026-08-15 065619.png"
  back  = "C:\Users\rober\Pictures\Screenshots\Screenshot 2026-08-15 065705.png"
}
$outDir = Join-Path $PSScriptRoot "..\Previews\assets"
New-Item -ItemType Directory -Force $outDir | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

public static class ImgProc
{
    public static void Cover(string src, string dst, int tw, int th, long quality)
    {
        using (Bitmap b = new Bitmap(src))
        using (Bitmap o = new Bitmap(tw, th))
        {
            using (Graphics g = Graphics.FromImage(o))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                double s = Math.Max((double)tw / b.Width, (double)th / b.Height);
                int w = (int)Math.Ceiling(b.Width * s), h = (int)Math.Ceiling(b.Height * s);
                g.DrawImage(b, (tw - w) / 2, (th - h) / 2, w, h);
            }
            ImageCodecInfo jpg = null;
            foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders())
                if (c.MimeType == "image/jpeg") jpg = c;
            EncoderParameters ep = new EncoderParameters(1);
            ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
            o.Save(dst, jpg, ep);
        }
    }

    // Removes a smooth studio backdrop: models the backdrop color across the frame from
    // border samples, classifies pixels by distance to the model, keeps only regions
    // connected to the border, then feathers the silhouette edge.
    public static void Cutout(string src, string dst, double tol, int targetH,
                              double topBarFrac, double wmWFrac, double wmHFrac)
    {
        Bitmap b = new Bitmap(src);
        int W = b.Width, H = b.Height;
        BitmapData bd = b.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int[] px = new int[W * H];
        System.Runtime.InteropServices.Marshal.Copy(bd.Scan0, px, 0, px.Length);
        b.UnlockBits(bd);

        // 1) border samples of the grey backdrop (skip near-black bars and near-white text)
        List<int[]> samples = new List<int[]>();
        Action<int, int> take = (x, y) =>
        {
            int p = px[y * W + x];
            int r = (p >> 16) & 255, g = (p >> 8) & 255, bl = p & 255;
            int lum = (r + g + bl) / 3;
            if (lum > 55 && lum < 200) samples.Add(new int[] { x, y, r, g, bl });
        };
        for (int x = 0; x < W; x += 6) { take(x, 2); take(x, H - 3); }
        for (int y = 0; y < H; y += 6) { take(2, y); take(W - 3, y); }

        // 2) coarse-grid IDW model of backdrop color, bilinear per pixel
        int GS = 32;
        int gw = W / GS + 2, gh = H / GS + 2;
        double[,] mr = new double[gw, gh], mg = new double[gw, gh], mb = new double[gw, gh];
        for (int gx = 0; gx < gw; gx++)
            for (int gy = 0; gy < gh; gy++)
            {
                double cx = gx * GS, cy = gy * GS, sr = 0, sg = 0, sb = 0, sw = 0;
                foreach (int[] s in samples)
                {
                    double dx = s[0] - cx, dy = s[1] - cy;
                    double w2 = 1.0 / (dx * dx + dy * dy + 1.0);
                    sr += s[2] * w2; sg += s[3] * w2; sb += s[4] * w2; sw += w2;
                }
                mr[gx, gy] = sr / sw; mg[gx, gy] = sg / sw; mb[gx, gy] = sb / sw;
            }

        // 3) classify: backdrop-like, forced bars/watermark, near-black borders
        bool[] isBg = new bool[W * H];
        int topBar = (int)(H * topBarFrac);
        int wmX = (int)(W * wmWFrac), wmY = (int)(H * (1.0 - wmHFrac));
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int i = y * W + x, p = px[i];
                int r = (p >> 16) & 255, g = (p >> 8) & 255, bl = p & 255;
                double fx = (double)x / GS, fy = (double)y / GS;
                int gx = (int)fx, gy = (int)fy;
                double tx = fx - gx, ty = fy - gy;
                double br = mr[gx, gy] * (1 - tx) * (1 - ty) + mr[gx + 1, gy] * tx * (1 - ty) + mr[gx, gy + 1] * (1 - tx) * ty + mr[gx + 1, gy + 1] * tx * ty;
                double bg2 = mg[gx, gy] * (1 - tx) * (1 - ty) + mg[gx + 1, gy] * tx * (1 - ty) + mg[gx, gy + 1] * (1 - tx) * ty + mg[gx + 1, gy + 1] * tx * ty;
                double bb = mb[gx, gy] * (1 - tx) * (1 - ty) + mb[gx + 1, gy] * tx * (1 - ty) + mb[gx, gy + 1] * (1 - tx) * ty + mb[gx + 1, gy + 1] * tx * ty;
                double d = Math.Sqrt((r - br) * (r - br) + (g - bg2) * (g - bg2) + (bl - bb) * (bl - bb));
                bool bgLike = d < tol;
                if (y < topBar) bgLike = true;
                if (x < wmX && y > wmY) bgLike = true;                       // watermark box
                int lum = (r + g + bl) / 3;
                if (lum < 45 && (x < 4 || y < 4 || x > W - 5 || y > H - 5)) bgLike = true;
                isBg[i] = bgLike;
            }

        // 4) keep only bg regions connected to the border
        bool[] removed = new bool[W * H];
        Queue<int> q = new Queue<int>();
        Action<int, int> push = (x, y) =>
        {
            int i = y * W + x;
            if (x >= 0 && x < W && y >= 0 && y < H && isBg[i] && !removed[i]) { removed[i] = true; q.Enqueue(i); }
        };
        for (int x = 0; x < W; x++) { push(x, 0); push(x, H - 1); }
        for (int y = 0; y < H; y++) { push(0, y); push(W - 1, y); }
        while (q.Count > 0)
        {
            int i = q.Dequeue(); int x = i % W, y = i / W;
            push(x - 1, y); push(x + 1, y); push(x, y - 1); push(x, y + 1);
        }

        // 4b) restore thin intrusions: removed pixels mostly surrounded by kept pixels
        for (int it = 0; it < 24; it++)
        {
            List<int> flips = new List<int>();
            for (int y = 1; y < H - 1; y++)
                for (int x = 1; x < W - 1; x++)
                {
                    int i = y * W + x;
                    if (!removed[i]) continue;
                    int kept = 0;
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                            if (!removed[i + dy * W + dx]) kept++;
                    if (kept >= 6) flips.Add(i);
                }
            if (flips.Count == 0) break;
            foreach (int i in flips) removed[i] = false;
        }

        // 4c) drop stray kept debris: keep only the largest kept component
        int[] label = new int[W * H];
        int nLabels = 0, bestLabel = 0, bestSize = 0;
        Queue<int> q2 = new Queue<int>();
        for (int s0 = 0; s0 < W * H; s0++)
        {
            if (removed[s0] || label[s0] != 0) continue;
            nLabels++;
            int size = 0;
            label[s0] = nLabels; q2.Enqueue(s0);
            while (q2.Count > 0)
            {
                int i = q2.Dequeue(); size++;
                int x = i % W, y = i / W;
                if (x > 0 && !removed[i - 1] && label[i - 1] == 0) { label[i - 1] = nLabels; q2.Enqueue(i - 1); }
                if (x < W - 1 && !removed[i + 1] && label[i + 1] == 0) { label[i + 1] = nLabels; q2.Enqueue(i + 1); }
                if (y > 0 && !removed[i - W] && label[i - W] == 0) { label[i - W] = nLabels; q2.Enqueue(i - W); }
                if (y < H - 1 && !removed[i + W] && label[i + W] == 0) { label[i + W] = nLabels; q2.Enqueue(i + W); }
            }
            if (size > bestSize) { bestSize = size; bestLabel = nLabels; }
        }
        for (int i = 0; i < W * H; i++)
            if (!removed[i] && label[i] != bestLabel) removed[i] = true;

        // 5) apply alpha + 1px feather, find bounds
        int minX = W, minY = H, maxX = 0, maxY = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int i = y * W + x;
                if (removed[i]) { px[i] = px[i] & 0x00FFFFFF; continue; }
                bool edge = (x > 0 && removed[i - 1]) || (x < W - 1 && removed[i + 1]) ||
                            (y > 0 && removed[i - W]) || (y < H - 1 && removed[i + W]);
                if (edge) px[i] = (px[i] & 0x00FFFFFF) | (140 << 24);
                if (x < minX) minX = x; if (x > maxX) maxX = x;
                if (y < minY) minY = y; if (y > maxY) maxY = y;
            }

        minX = Math.Max(0, minX - 6); minY = Math.Max(0, minY - 6);
        maxX = Math.Min(W - 1, maxX + 6); maxY = Math.Min(H - 1, maxY + 6);
        int cw = maxX - minX + 1, ch = maxY - minY + 1;

        Bitmap cut = new Bitmap(cw, ch, PixelFormat.Format32bppArgb);
        BitmapData cd = cut.LockBits(new Rectangle(0, 0, cw, ch), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        int[] cpx = new int[cw * ch];
        for (int y = 0; y < ch; y++)
            for (int x = 0; x < cw; x++)
                cpx[y * cw + x] = px[(y + minY) * W + (x + minX)];
        System.Runtime.InteropServices.Marshal.Copy(cpx, 0, cd.Scan0, cpx.Length);
        cut.UnlockBits(cd);

        int tw2 = (int)Math.Round((double)cw * targetH / ch);
        using (Bitmap o = new Bitmap(tw2, targetH, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(o))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(cut, 0, 0, tw2, targetH);
            }
            o.Save(dst, ImageFormat.Png);
        }
        cut.Dispose(); b.Dispose();
        Console.WriteLine(dst + " " + tw2 + "x" + targetH);
    }
}
"@ -ReferencedAssemblies System.Drawing

[ImgProc]::Cover($src.bg, (Join-Path $outDir "bg.jpg"), 1600, 900, 72)
[ImgProc]::Cutout($src.front, (Join-Path $outDir "soldier_front.png"), 20, 640, 0.028, 0.32, 0.22)
[ImgProc]::Cutout($src.back,  (Join-Path $outDir "soldier_back.png"),  20, 640, 0.012, 0.0,  0.0)

foreach ($f in @("bg.jpg","soldier_front.png","soldier_back.png")) {
  $p = Join-Path $outDir $f
  [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) | Set-Content -Encoding ascii "$p.b64.txt"
  "{0}  {1:n0} bytes" -f $f, (Get-Item $p).Length
}
$font = "E:\Fallout 4 Modding\F4SE\FallUI HUDs\S2 HUD Rework\Build\OptionalFontReplacer\ArimoStalkerBold\Probe\Arimo-Stalker-Bold.ttf"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($font)) | Set-Content -Encoding ascii (Join-Path $outDir "font.b64.txt")
"font.b64.txt written"