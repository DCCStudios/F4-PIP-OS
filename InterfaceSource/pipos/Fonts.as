package pipos
{
   import flash.text.Font;

   // Embedded Arimo Stalker Bold (Apache 2.0) -- the locked M1 typeface. Scaleform/FO4 has no OS font
   // provider, so device fonts (_sans/Arial) draw nothing in game; the font MUST be embedded and
   // rendered with embedFonts=true. embedAsCFF="false" is REQUIRED so mxmlc emits a DefineFont3 tag
   // (Scaleform GFx cannot render the CFF/DefineFont4 that Flash 10+ emits by default).
   // The font is compiled into each page SWF (pages share no runtime font). The glyph range is WIDENED
   // (0.0.30) beyond Basic Latin to cover the special characters that appear in real weapon-mod / quest /
   // station names -- Latin-1 accented letters, hyphens/dashes, curly quotes, bullet, ellipsis, (TM) -- so
   // they render NATIVELY instead of being flattened. This range + Theme.sanitize() close ONLY the
   // UNFONTABLE-GLYPH FindFont crash class (a glyph outside the embedded range formatted with no device-font
   // fallback -> FindFont(NULL)); Theme.inRange() MUST mirror this range exactly. It does NOT close the OTHER
   // FindFont class -- a script geometry-write (.width= et al.) on a fresh/EMPTY field inside interaction
   // dispatch, which is glyph-independent and is fixed structurally by pooling/update-only handlers (see
   // pipos/PipList.as and each page's buildText). Both fixes ship together.
   //   U+0020-U+007E Basic Latin | U+00A0-U+00FF Latin-1 Supplement | U+2010-U+2022 dashes/quotes/bullet
   //   U+2026 ellipsis | U+2122 (TM).  Single code points expressed as one-char ranges so the Flex font
   //   transcoder parses them unambiguously. Marker glyphs (favorite/legendary) stay vector, not font glyphs.
   public class Fonts
   {
      [Embed(source="Arimo-Stalker-Bold.ttf", fontName="PipOSFont", mimeType="application/x-font",
             embedAsCFF="false", advancedAntiAliasing="true",
             unicodeRange="U+0020-U+007E,U+00A0-U+00FF,U+2010-U+2022,U+2026-U+2026,U+2122-U+2122")]
      private static var _Face:Class;

      public static const NAME:String = "PipOSFont";
      private static var _registered:Boolean = false;

      public static function register():String
      {
         if (!_registered)
         {
            try { Font.registerFont(_Face); } catch (e:Error) {}
            _registered = true;
         }
         return NAME;
      }
   }
}
