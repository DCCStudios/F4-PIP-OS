package
{
   import flash.display.MovieClip;
   import flash.display.Shape;

   // PIP-OS override of Baka Fullscreen Pip-Boy's PipboyBackgroundMenu.swf (1920x1080, 16:9 first).
   // This is the FULL-SCREEN CRT FRAMING layer that surrounds the scaled 876x700 menu: outer bezel,
   // corner brackets, vignette, and the scanline field. Authored to be a drop-in that preserves Baka's
   // contract shape: document class named PipboyBackgroundMenu with a Background_mc child (matching the
   // decompiled Baka class). Baka's DLL scales/positions the menu over this background.
   //
   // NOTE: Baka's original extends Shared.AS3.IMenu (a Bethesda base embedded in its SWF). Reproducing
   // that whole base is out of scope; this extends MovieClip and keeps the Background_mc instance. This
   // is BUILT-UNVERIFIED against Baka's DLL in game -- see README/ImplementationNotes for the risk and
   // the fallback (do not install this file; keep Baka's background).
   public class PipboyBackgroundMenu extends MovieClip
   {
      private static const W:Number = 1920;
      private static const H:Number = 1080;
      // phosphor palette (kept local so the background SWF embeds no font/other classes)
      private static const GROUND:uint = 0x060A06;
      private static const PHOS:uint = 0x86E08C;
      private static const PHOS_BRIGHT:uint = 0xC9F7C4;
      private static const PHOS_DIM:uint = 0x2B4A33;

      public var Background_mc:MovieClip;

      public function PipboyBackgroundMenu()
      {
         super();
         this.Background_mc = new MovieClip();
         addChild(this.Background_mc);
         this.draw();
      }

      private function draw():void
      {
         var g:* = this.Background_mc.graphics;
         // dark phosphor ground
         g.beginFill(GROUND, 1); g.drawRect(0, 0, W, H); g.endFill();

         // vignette: successively darker inset frames toward the edges
         var i:int;
         for (i = 0; i < 8; i++)
         {
            var inset:Number = i * 26;
            g.beginFill(0x000000, 0.06);
            g.drawRect(inset, inset, W - 2 * inset, 26);
            g.drawRect(inset, H - inset - 26, W - 2 * inset, 26);
            g.drawRect(inset, inset, 26, H - 2 * inset);
            g.drawRect(W - inset - 26, inset, 26, H - 2 * inset);
            g.endFill();
         }

         // scanline field (whole screen; the menu scales over this)
         g.lineStyle(1, PHOS, 0.04);
         var y:Number = 0;
         while (y < H) { g.moveTo(0, y); g.lineTo(W, y); y += 3; }
         g.lineStyle();

         // outer CRT bezel: double frame + corner brackets near the screen edges
         var m:Number = 48;
         g.lineStyle(3, PHOS, 0.45); g.drawRect(m, m, W - 2 * m, H - 2 * m);
         g.lineStyle(1, PHOS_DIM, 0.5); g.drawRect(m + 8, m + 8, W - 2 * m - 16, H - 2 * m - 16);
         this.brackets(g, m - 8, m - 8, W - 2 * m + 16, H - 2 * m + 16, 64, PHOS_BRIGHT, 0.85);
      }

      private function brackets(g:*, x:Number, y:Number, w:Number, h:Number, len:Number, color:uint, alpha:Number):void
      {
         g.lineStyle(3, color, alpha);
         g.moveTo(x, y + len); g.lineTo(x, y); g.lineTo(x + len, y);
         g.moveTo(x + w - len, y); g.lineTo(x + w, y); g.lineTo(x + w, y + len);
         g.moveTo(x, y + h - len); g.lineTo(x, y + h); g.lineTo(x + len, y + h);
         g.moveTo(x + w - len, y + h); g.lineTo(x + w, y + h); g.lineTo(x + w, y + h - len);
         g.lineStyle();
      }
   }
}
