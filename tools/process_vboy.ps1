# Turn the Meshy Vault Boy (green-on-black glow) into a clean transparent phosphor asset:
# figure mask by luminance + internal hole fill (keeps black outlines), recolor to phosphor, crop, scale.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$gen = Join-Path $PSScriptRoot "..\Previews\assets\gen"
$src = Join-Path $gen "vboy_gen_raw.png"
$dst = Join-Path $gen "vaultboy.png"

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;
public static class VBoy {
  public static void Process(string src, string dst, int targetH) {
    Bitmap b = new Bitmap(src);
    int W=b.Width, H=b.Height;
    BitmapData bd=b.LockBits(new Rectangle(0,0,W,H),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
    int[] px=new int[W*H]; System.Runtime.InteropServices.Marshal.Copy(bd.Scan0,px,0,px.Length); b.UnlockBits(bd);
    float[] lum=new float[W*H];
    for(int i=0;i<W*H;i++){int p=px[i];int r=(p>>16)&255,g=(p>>8)&255,bl=p&255;lum[i]=(0.299f*r+0.587f*g+0.114f*bl);}
    // figure = bright green body
    bool[] mask=new bool[W*H];
    for(int i=0;i<W*H;i++) mask[i]= lum[i] > 96f;
    // fill internal holes (dark outlines surrounded by figure): flood non-mask from border, survivors are holes
    bool[] outside=new bool[W*H]; Queue<int> q=new Queue<int>();
    Action<int,int> push=(x,y)=>{int i=y*W+x; if(x>=0&&x<W&&y>=0&&y<H&&!mask[i]&&!outside[i]){outside[i]=true;q.Enqueue(i);}};
    for(int x=0;x<W;x++){push(x,0);push(x,H-1);} for(int y=0;y<H;y++){push(0,y);push(W-1,y);}
    while(q.Count>0){int i=q.Dequeue();int x=i%W,y=i/W;push(x-1,y);push(x+1,y);push(x,y-1);push(x,y+1);}
    for(int i=0;i<W*H;i++) if(!mask[i] && !outside[i]) mask[i]=true; // internal holes -> figure
    // keep only largest component
    int[] lab=new int[W*H]; int best=0,bestN=0,nl=0;
    for(int s=0;s<W*H;s++){ if(!mask[s]||lab[s]!=0) continue; nl++; int n=0; lab[s]=nl; q.Enqueue(s);
      while(q.Count>0){int i=q.Dequeue();n++;int x=i%W,y=i/W;
        if(x>0&&mask[i-1]&&lab[i-1]==0){lab[i-1]=nl;q.Enqueue(i-1);}
        if(x<W-1&&mask[i+1]&&lab[i+1]==0){lab[i+1]=nl;q.Enqueue(i+1);}
        if(y>0&&mask[i-W]&&lab[i-W]==0){lab[i-W]=nl;q.Enqueue(i-W);}
        if(y<H-1&&mask[i+W]&&lab[i+W]==0){lab[i+W]=nl;q.Enqueue(i+W);}}
      if(n>bestN){bestN=n;best=nl;} }
    for(int i=0;i<W*H;i++) if(mask[i]&&lab[i]!=best) mask[i]=false;
    // recolor: phosphor * normalized luma; alpha from mask with 1px feather
    int minX=W,minY=H,maxX=0,maxY=0;
    int[] outp=new int[W*H];
    for(int y=0;y<H;y++)for(int x=0;x<W;x++){int i=y*W+x;
      if(!mask[i]){outp[i]=0;continue;}
      float L=Math.Min(1f, lum[i]/210f*1.15f);
      int r=(int)(134*L), g=(int)(224*L), bl=(int)(140*L);
      bool edge=(x>0&&!mask[i-1])||(x<W-1&&!mask[i+1])||(y>0&&!mask[i-W])||(y<H-1&&!mask[i+W]);
      int a= edge?170:255;
      outp[i]=(a<<24)|(r<<16)|(g<<8)|bl;
      if(x<minX)minX=x; if(x>maxX)maxX=x; if(y<minY)minY=y; if(y>maxY)maxY=y;
    }
    minX=Math.Max(0,minX-6);minY=Math.Max(0,minY-6);maxX=Math.Min(W-1,maxX+6);maxY=Math.Min(H-1,maxY+6);
    int cw=maxX-minX+1, ch=maxY-minY+1;
    Bitmap cut=new Bitmap(cw,ch,PixelFormat.Format32bppArgb);
    BitmapData cd=cut.LockBits(new Rectangle(0,0,cw,ch),ImageLockMode.WriteOnly,PixelFormat.Format32bppArgb);
    int[] cpx=new int[cw*ch];
    for(int y=0;y<ch;y++)for(int x=0;x<cw;x++) cpx[y*cw+x]=outp[(y+minY)*W+(x+minX)];
    System.Runtime.InteropServices.Marshal.Copy(cpx,0,cd.Scan0,cpx.Length); cut.UnlockBits(cd);
    int tw=(int)Math.Round((double)cw*targetH/ch);
    Bitmap o=new Bitmap(tw,targetH,PixelFormat.Format32bppArgb);
    using(Graphics g=Graphics.FromImage(o)){g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(cut,0,0,tw,targetH);}
    o.Save(dst,ImageFormat.Png);
    Console.WriteLine(tw+"x"+targetH);
    cut.Dispose();o.Dispose();b.Dispose();
  }
}
"@ -ReferencedAssemblies System.Drawing

[VBoy]::Process($src, $dst, 560)
[Convert]::ToBase64String([IO.File]::ReadAllBytes($dst)) | Set-Content -Encoding ascii "$dst.b64.txt"
"saved vaultboy.png"