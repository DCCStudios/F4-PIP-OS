package pipos
{
   import flash.display.Graphics;
   import flash.display.Sprite;
   import flash.filters.DropShadowFilter;
   import flash.filters.GlowFilter;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;

   // PIP-OS phosphor palette + drawing helpers, translated from Previews/pipos-mockup.template.html.
   public class Theme
   {
      public static const GROUND:uint     = 0x060A06;
      // 0.0.52 LIFECYCLE BREADCRUMBS (STAT-install forensics). Pages/chrome append short marks at each lifecycle
      // step (ctor / panels / stage / text / first-event). Statics are SHARED across all page SWFs in the shell's
      // ApplicationDomain (first-def-wins), so the CHROME mirrors this trail onto its own public var each tick and
      // the DLL logs it -- giving in-game proof of exactly how far each page's class got, even when a page never
      // renders. String appends only (no TextField, no geometry): crash-law-safe in any context including ctors.
      public static var LIFE:String = "";
      public static function life(m:String):void
      {
         if (LIFE.length < 700) { LIFE += (LIFE.length > 0 ? ">" : "") + m; }
      }

      public static const PHOS:uint        = 0x86E08C;
      public static const PHOS_BRIGHT:uint = 0xC9F7C4;
      public static const PHOS_DIM:uint    = 0x4D7A53;
      public static const PHOS_FAINT:uint  = 0x2B4A33;
      public static const SEL:uint         = 0x5FCE67;
      public static const SEL_INK:uint     = 0xF2FBF2;
      public static const WARN:uint        = 0xE2B95C;
      public static const CRIT:uint        = 0xE0654F;
      public static const PANEL:uint       = 0x081610;   // rgba(8,22,12,.78) -> solid approx
      public static const LINE:uint        = 0x86E08C;

      // ============================================================================================
      // 16:9 WIDESCREEN RE-AUTHOR (0.0.24-WIDE). Supersedes the 876x700 layout. Loaded child SWFs (pages)
      // and the DLL-attached chrome render in the ROOT (root1-local) coordinate space. The 16:9 SPIKE
      // measured (ShowAll, 4K) a usable movie-unit budget in root1-local of roughly
      //     X in [-238, 1114]  (width ~1352)   Y in [0, 761]  (height ~761)   aspect 1.777 == 16:9.
      // The M1 mockup canvas (Previews/pipos-mockup.template.html) is a pure 1600x900 16:9 stage. We map
      // that canvas onto the budget with a single UNIFORM scale MS and an origin (FX,FY), INSET on every
      // side so a coordinate-mapping error can never clip content off-screen: canvas(0,0) -> (FX,FY),
      // canvas(1600,900) -> (FX+1280, FY+720) == (1080, 744), comfortably inside [-238,1114]x[0,761].
      //
      // *** SINGLE-KNOB ORIGIN FIX ***  If the first widescreen screenshot is shifted, this is a ONE-NUMBER
      // change (no re-layout): every page + chrome coordinate is derived from mx()/my()/ms().
      //   - content too far RIGHT  -> decrease FX ;  too far LEFT  -> increase FX
      //   - content too far DOWN   -> decrease FY ;  too far UP    -> increase FY
      //   - content too BIG/SMALL  -> decrease/increase MS (keep FX/FY, re-centers from the top-left origin)
      public static const MS:Number = 0.8;    // mockup-px -> root1-local unit (1600*0.8=1280, 900*0.8=720)
      // FONT SCALE (0.0.40 fidelity pass): the LAYOUT is scaled by MS (mockup-px -> local) but font SIZES were
      // historically passed to the factories at the mockup's RAW px, so text rendered ~1/MS too big/loose for the
      // scaled boxes. fs() scales an incoming (mockup-px) font size by FONTSCALE so a mockup size renders at the
      // right proportion on the 1280x720 local canvas. Every field factory (tf/mk/heading/keycap/meterInto/
      // chipInto and the page-level Theme.mk/tf calls) routes its size through fs(), so this is the SINGLE knob for
      // the whole app's type scale. Min 8px keeps small labels legible under GFx. Set at field-build time only
      // (never on an interaction/tick path) -> crash-law-legal.
      public static const FONTSCALE:Number = 0.8;
      public static function fs(px:Number):int { var v:int = Math.round(px * FONTSCALE); return (v < 8) ? 8 : v; }
      public static const FX:Number = -200;   // mockup x=0 -> local x   (canvas right edge -> +1080)
      public static const FY:Number = 24;     // mockup y=0 -> local y   (canvas bottom edge -> +744)
      public static function mx(v:Number):Number { return FX + v * MS; }   // mockup X -> local X
      public static function my(v:Number):Number { return FY + v * MS; }   // mockup Y -> local Y
      public static function ms(v:Number):Number { return v * MS; }        // mockup size -> local size

      // Mockup canvas extent in local units (chrome frame border, CRT overlay coverage).
      public static const SW:Number = 1280;  // ms(1600)
      public static const SH:Number = 720;   // ms(900)

      // Main content region == mockup `main` (left 240, right x=1566, top 60, bottom y=804).
      public static const CX:Number = FX + 240 * MS;    // -8      content left edge (right of the sidebar)
      public static const CR:Number = FX + 1566 * MS;   // 1052.8  content right edge
      public static const CW:Number = (1566 - 240) * MS;// 1060.8  content width
      // Top band: the sub-tab strip is the top row of `main` (mockup y60); the content grid begins below
      // it (mockup subtabs 40 + margin 12 => y112). No standalone page title (the sidebar shows the page).
      public static const SUB_Y:Number = FY + 60 * MS;   // 72      sub-tab strip top
      public static const BY:Number    = FY + 112 * MS;  // 113.6   grid / body top
      public static const BB:Number    = FY + 804 * MS;  // 667.2   grid / body bottom (== main bottom)
      public static const TITLE_Y:Number = FY + 30 * MS; // 48      (legacy; titles are hidden this round)
      public static const INFO_R:Number = FX + 1566 * MS;// 1052.8  right-align limit for top readouts (== CR)

      // Round-7 layout-hygiene constants (make clearance a rule, not a per-spot hand-tune):
      // PAD = uniform inner inset for every panel; nothing (bar/text/tile/row) touches a panel border.
      public static const PAD:Number = 12;
      public static const GUTTER:Number = 12;
      public static const KEYBAR_Y:Number = FY + 812 * MS; // ~674 (no keybar drawn; kept for clearance refs)

      // FallUI / Complex Sorter tag-folder grouping master switch. When true, tagged inventories (names carrying
      // a leading [..]/{..}/(..) category tag) are grouped under collapsible folder headers; an un-tagged
      // inventory renders flat regardless. Stub for a later Menu Framework settings toggle (this round only reads it).
      public static const FOLDERS:Boolean = true;

      // Embedded Arimo Stalker Bold (pipos.Fonts). Registered on first use; all TextFields use
      // embedFonts=true so text renders under Scaleform GFx (device fonts draw nothing in game).
      public static var FONT:String = Fonts.register();

      public static function tf(size:int, color:uint, bold:Boolean = false, align:String = "left"):TextField
      {
         var t:TextField = new TextField();
         t.selectable = false;
         t.mouseEnabled = false;
         t.multiline = false;
         t.embedFonts = true;
         t.antiAliasType = "advanced";
         t.autoSize = (align == "right") ? TextFieldAutoSize.RIGHT : (align == "center" ? TextFieldAutoSize.CENTER : TextFieldAutoSize.LEFT);
         var fmt:TextFormat = new TextFormat(FONT, fs(size), color, bold);
         fmt.align = align;
         fmt.letterSpacing = 0.5;
         t.defaultTextFormat = fmt;
         return t;
      }

      // Locked M1 selected-row style: near-white ink with a dark drop shadow on the green bar.
      // V1: GFx does not reliably apply defaultTextFormat to .text on a field created in code -> the
      // label renders at a giant default size in the wrong colour. Force the format onto the text.
      // UNCONDITIONAL attach-before-mutate: create + addChild so ANY later width/text is safe (a page
      // constructed via ProcessLoadQueue formats text in its ctor before a font context exists -> FindFont
      // NULL AV; proven by the RADIO ctor crash). Use mk()+setText() for every code-created label.
      public static function mk(parent:Sprite, size:int, color:uint, bold:Boolean = false, align:String = "left"):TextField
      {
         var t:TextField = tf(size, color, bold, align);
         parent.addChild(t);
         return t;
      }

      // ============================================================================================
      // TWO SEPARATE FindFont(NULL) CRASH CLASSES -- sanitize covers ONE of them (0.0.31 corrected diagnosis):
      //   (1) UNFONTABLE GLYPH (the older, texted-field class). The embedded font (pipos.Fonts) covers only a
      //       Unicode subset and GFx has no device-font fallback; formatting a glyph outside the range returns
      //       a null font handle -> AV. sanitize() below GUARANTEES every display string is inside the embedded
      //       range, so this class cannot fire. NECESSARY but NOT sufficient.
      //   (2) GEOMETRY-WRITE ON A FRESH/EMPTY FIELD IN INTERACTION DISPATCH (the class that still crashed 0.0.30
      //       on a quest click). A `.width =` (or .x/.y/.height/.autoSize) on a just-attached EMPTY TextField
      //       inside a mouse-click's GenerateMouseEvents (or the data-change the engine pushes synchronously
      //       inside that click) reformats before the font handle resolves -> SetWidth -> Format -> FindFont
      //       (NULL). This is GLYPH-INDEPENDENT (the field had no text), so sanitize cannot stop it. The
      //       STRUCTURAL fix is pooling + update-only handlers (PipList.buildPool, page buildText): create every
      //       field and write every geometry ONCE in the build window, never on an interaction-reachable path.
      // sanitize is retained for class (1); pooling/update-only is the fix for class (2). Every setText routes
      // through sanitize.
      //
      // Embedded range (MUST mirror pipos/Fonts.as exactly):
      //   U+0020-U+007E  Basic Latin (printable ASCII)
      //   U+00A0-U+00FF  Latin-1 Supplement (accented letters, (c) (r) (deg) middle-dot ...)
      //   U+2010-U+2022  hyphens/dashes, curly single/double quotes, bullet
      //   U+2026         horizontal ellipsis
      //   U+2122         trade mark
      // In-range chars pass through unchanged (native rendering). Out-of-range chars are mapped to an in-range
      // equivalent for readability, or replaced with '?' as the last-resort guarantee. Pure char-code scan.
      private static function inRange(c:int):Boolean
      {
         return (c >= 0x20 && c <= 0x7E) ||
                (c >= 0xA0 && c <= 0xFF) ||
                (c >= 0x2010 && c <= 0x2022) ||
                c == 0x2026 || c == 0x2122;
      }

      public static function sanitize(s:String):String
      {
         if (s == null) { return ""; }
         var n:int = s.length;
         var out:String = "";
         for (var i:int = 0; i < n; i++)
         {
            var c:int = s.charCodeAt(i);
            // Control chars (< 0x20) are NOT glyph lookups. Preserve the ones that carry meaning instead of
            // garbling them to '?': newline is a paragraph break (safe in multiline fields -- quest description,
            // debug dump), tab -> two spaces. CR / CRLF normalise to a single LF. Everything else drops.
            if (c < 0x20)
            {
               if (c == 0x0A) { out += "\n"; }                                                     // LF -> keep
               else if (c == 0x0D) { if (i + 1 < n && s.charCodeAt(i + 1) == 0x0A) { i++; } out += "\n"; }  // CR / CRLF -> LF
               else if (c == 0x09) { out += "  "; }                                                // tab -> two spaces
               // else: other control chars dropped
               continue;
            }
            if (inRange(c))
            {
               // In-range. Normalise a couple of whitespace/format oddities that render as boxes/gaps even
               // though their code point is technically inside the Latin-1 block.
               if (c == 0xA0) { out += " "; }        // NBSP -> normal space
               else if (c == 0xAD) { /* soft hyphen -> drop */ }
               else { out += s.charAt(i); }
               continue;
            }
            // Out-of-range: map common typographics to an in-range equivalent (belt-and-braces: most of these
            // are ALREADY in-range above and pass through natively; these cases only fire if the range is ever
            // narrowed). Anything else becomes '?'. The output is 100% within the embedded range either way.
            switch (c)
            {
               case 0x2018: case 0x2019: case 0x201A: case 0x201B: case 0x2032: out += "'"; break;   // ' ' -> '
               case 0x201C: case 0x201D: case 0x201E: case 0x201F: case 0x2033: out += "\""; break;  // " " -> "
               case 0x2013: case 0x2014: case 0x2015: case 0x2212: out += "-"; break;                 // dashes/minus -> -
               case 0x2022: case 0x00B7: case 0x2027: case 0x2219: out += "*"; break;                 // bullet/dot -> *
               case 0x2026: out += "..."; break;                                                      // ellipsis -> ...
               case 0x2122: out += "(TM)"; break;                                                     // (TM)
               case 0x00A9: out += "(C)"; break;
               case 0x00AE: out += "(R)"; break;
               case 0x2000: case 0x2001: case 0x2002: case 0x2003: case 0x2004: case 0x2005:
               case 0x2006: case 0x2007: case 0x2008: case 0x2009: case 0x200A:
               case 0x202F: case 0x205F: case 0x3000: out += " "; break;                              // Unicode spaces -> space
               case 0x200B: case 0x200C: case 0x200D: case 0x2028: case 0x2029: case 0xFEFF: break;   // zero-width/line/para -> drop
               default: out += "?"; break;                                                            // exotic (CJK/emoji/...) -> ?
            }
         }
         return out;
      }

      public static function setText(t:TextField, str:String):void
      {
         t.text = sanitize(str);
         if (t.length > 0) { t.setTextFormat(t.defaultTextFormat); }
      }

      public static function selectedInk(t:TextField):void
      {
         t.textColor = SEL_INK;
         t.filters = [new DropShadowFilter(1.5, 45, 0x0A140A, 0.9, 3, 3, 1, 2)];
      }

      // Vector marker glyphs (font-independent). Favorite = 5-point star; legendary = 4-point sparkle.
      public static function star(g:Graphics, cx:Number, cy:Number, r:Number, color:uint):void
      {
         g.lineStyle();   // G1: no stroke -> no diagonal streak between successive glyphs
         g.beginFill(color, 1);
         for (var i:int = 0; i < 10; i++)
         {
            var rad:Number = (i % 2 == 0) ? r : r * 0.45;
            var a:Number = -Math.PI / 2 + i * Math.PI / 5;
            var x:Number = cx + Math.cos(a) * rad, y:Number = cy + Math.sin(a) * rad;
            if (i == 0) { g.moveTo(x, y); } else { g.lineTo(x, y); }
         }
         g.endFill();
      }
      public static function sparkle(g:Graphics, cx:Number, cy:Number, r:Number, color:uint):void
      {
         g.lineStyle();   // G1: fill-only glyph
         g.beginFill(color, 1);
         g.moveTo(cx, cy - r); g.lineTo(cx + r * 0.28, cy - r * 0.28);
         g.lineTo(cx + r, cy); g.lineTo(cx + r * 0.28, cy + r * 0.28);
         g.lineTo(cx, cy + r); g.lineTo(cx - r * 0.28, cy + r * 0.28);
         g.lineTo(cx - r, cy); g.lineTo(cx - r * 0.28, cy - r * 0.28);
         g.endFill();
      }
      // 0.0.60 LEGENDARY MARKER: hollow diamond with a center dot -- a clearly different SILHOUETTE from the
      // favorite star (field feedback: the 4-point sparkle still read as "another star" at 5-6px). Fill-only.
      public static function legendaryMark(g:Graphics, cx:Number, cy:Number, r:Number, color:uint):void
      {
         g.lineStyle();
         g.beginFill(color, 1);
         // outer rhombus
         g.moveTo(cx, cy - r); g.lineTo(cx + r * 0.7, cy); g.lineTo(cx, cy + r); g.lineTo(cx - r * 0.7, cy);
         g.endFill();
         // punch the middle back out (darker inner rhombus) then a bright center dot
         g.beginFill(0x0A140A, 1);
         g.moveTo(cx, cy - r * 0.55); g.lineTo(cx + r * 0.38, cy); g.lineTo(cx, cy + r * 0.55); g.lineTo(cx - r * 0.38, cy);
         g.endFill();
         g.beginFill(color, 1); g.drawCircle(cx, cy, r * 0.18); g.endFill();
      }

      // Mockup .panel: translucent dark fill, rounded 8px, hairline edge, + 4 corner accent ticks.
      public static function panel(g:Graphics, x:Number, y:Number, w:Number, h:Number, borderAlpha:Number = 0.38):void
      {
         g.beginFill(PANEL, 0.82);
         g.drawRoundRect(x, y, w, h, 8, 8);
         g.endFill();
         g.lineStyle(1, LINE, borderAlpha);
         g.drawRoundRect(x + 0.5, y + 0.5, w - 1, h - 1, 8, 8);
         g.lineStyle();
         // corner accent ticks: SUBTLE (mockup .panel is a plain rounded border; keep only a faint CRT hint).
         // 0.0.41: shortened 9->5 and lightened (was borderAlpha+0.3 capped .8, ~0.68) to sit close to the mockup.
         var t:Number = 5;
         g.lineStyle(1, PHOS, Math.min(0.4, borderAlpha));
         g.moveTo(x + 4, y + 4 + t); g.lineTo(x + 4, y + 4); g.lineTo(x + 4 + t, y + 4);
         g.moveTo(x + w - 4 - t, y + 4); g.lineTo(x + w - 4, y + 4); g.lineTo(x + w - 4, y + 4 + t);
         g.moveTo(x + 4, y + h - 4 - t); g.lineTo(x + 4, y + h - 4); g.lineTo(x + 4 + t, y + h - 4);
         g.moveTo(x + w - 4 - t, y + h - 4); g.lineTo(x + w - 4, y + h - 4); g.lineTo(x + w - 4, y + h - 4 - t);
         g.lineStyle();
      }

      // Draw a panel AND register its rect (for the round-7 DEBUG clearance overlay). Pages collect
      // their panels into a _panels array exposed via debugRects(); the CompositeHost strokes each rect
      // plus its PAD inset so any content crossing a border is visible.
      public static function panelR(g:Graphics, rects:Array, x:Number, y:Number, w:Number, h:Number, borderAlpha:Number = 0.38):void
      {
         panel(g, x, y, w, h, borderAlpha);
         if (rects != null) { rects.push({ x:x, y:y, w:w, h:h }); }
      }

      // Bright heading with a subtle phosphor glow (mockup glow on headings/values).
      public static function glow(t:TextField, color:uint = 0x86E08C, strength:Number = 1):void
      {
         t.filters = [new GlowFilter(color, 0.55, 6, 6, strength, 1, false, false)];
      }

      // Panel heading (BRIGHT uppercase label, mockup .panel h-label). Adds to container, returns the field.
      // 0.0.46: was PHOS_DIM; the mockup panel headings (EQUIPMENT / INVENTORY / ACTIVE EFFECTS / ...) are bright
      // phosphor, so this is PHOS_BRIGHT to match (user: "the EQUIPMENT/INVENTORY text should be brighter").
      public static function heading(c:Sprite, x:Number, y:Number, text:String):TextField
      {
         var t:TextField = mk(c, 12, PHOS_BRIGHT, true); t.x = x; t.y = y;
         var fmt:TextFormat = t.defaultTextFormat; fmt.letterSpacing = 1.4; t.defaultTextFormat = fmt;
         setText(t, text); return t;
      }

      // Framed meter (mockup .meter): LABEL .... value on top, then a bordered bar with inner fill.
      public static function meterInto(c:Sprite, x:Number, y:Number, w:Number, label:String, valStr:String, frac:Number, color:uint):void
      {
         var lbl:TextField = mk(c, 11, PHOS_BRIGHT, true); lbl.x = x; lbl.y = y;   // 0.0.46: bright HP/AP/RADS labels (mockup)
         var lf:TextFormat = lbl.defaultTextFormat; lf.letterSpacing = 1.6; lbl.defaultTextFormat = lf; setText(lbl, label);
         var vv:TextField = mk(c, 12, color, true, "right"); vv.y = y; setText(vv, valStr); vv.x = x + w - vv.width;
         var by:Number = y + 20;
         var g:* = c.graphics;
         g.lineStyle(1, color, 0.5); g.drawRoundRect(x, by, w, 10, 3, 3); g.lineStyle();
         g.beginFill(0x000000, 0.4); g.drawRoundRect(x + 1, by + 1, w - 2, 8, 2, 2); g.endFill();
         if (frac < 0) { frac = 0; } if (frac > 1) { frac = 1; }
         g.beginFill(color, 0.9); g.drawRoundRect(x + 1, by + 1, (w - 2) * frac, 8, 2, 2); g.endFill();
      }

      // A rounded value chip with optional dim label (mockup WEIGHT/CAPS + W/V chips). Returns width.
      public static function chipInto(c:Sprite, x:Number, y:Number, iconFn:Function, label:String, value:String):Number
      {
         var pad:Number = 8, ih:Number = 22;
         var vT:TextField = mk(c, 12, PHOS_BRIGHT, true); setText(vT, value);
         var lT:TextField = null; var lw:Number = 0;
         if (label != null && label.length > 0) { lT = mk(c, 11, PHOS_DIM, true); setText(lT, label); lw = lT.width + 5; }
         var iconW:Number = (iconFn != null) ? 20 : 0;
         var w:Number = pad + iconW + lw + vT.width + pad;
         var g:* = c.graphics;
         g.lineStyle(1, LINE, 0.4); g.drawRoundRect(x, y, w, ih, 6, 6); g.lineStyle();
         var cx:Number = x + pad;
         if (iconFn != null) { iconFn(g, cx, y + 4, 14, PHOS); cx += iconW; }
         if (lT != null) { lT.x = cx; lT.y = y + 4; cx += lw; }
         vT.x = cx; vT.y = y + 3;
         return w;
      }

      // Boxed key glyph + label for the footer keybar (mockup .key). Returns total width. Adds to c.
      // NOTE: keycap is BUILD-TIME only (footer keybar assembly), never reached from a click/key/data handler,
      // and already writes geometry (autoSize/width/height/x/y) on the FRESH field BEFORE setText -- so the
      // kT.width= below is safe (crash class (2) only fires on interaction-reachable paths).
      public static function keycap(c:Sprite, x:Number, y:Number, key:String, label:String):Number
      {
         var kT:TextField = mk(c, 12, PHOS_BRIGHT, true, "center"); kT.autoSize = "none";
         var kw:Number = Math.max(22, key.length * 9 + 10);
         kT.width = kw; kT.height = 20; kT.x = x; kT.y = y + 3; setText(kT, key);
         var g:* = c.graphics;
         g.lineStyle(1, LINE, 0.5); g.drawRoundRect(x, y, kw, 24, 5, 5); g.lineStyle();
         var lT:TextField = mk(c, 12, PHOS, true); lT.x = x + kw + 7; lT.y = y + 4;
         var lf:TextFormat = lT.defaultTextFormat; lf.letterSpacing = 0.8; lT.defaultTextFormat = lf; setText(lT, label);
         return kw + 7 + lT.width;
      }

      // Small vector glyphs / icons (drawn, no bitmaps, font-independent).
      public static function diamond(g:Graphics, cx:Number, cy:Number, r:Number, color:uint):void
      {
         g.beginFill(color, 1); g.moveTo(cx, cy - r); g.lineTo(cx + r, cy); g.lineTo(cx, cy + r); g.lineTo(cx - r, cy); g.endFill();
      }
      public static function caret(g:Graphics, cx:Number, cy:Number, up:Boolean, color:uint):void
      {
         g.beginFill(color, 1);
         if (up) { g.moveTo(cx, cy - 3); g.lineTo(cx + 4, cy + 3); g.lineTo(cx - 4, cy + 3); }
         else    { g.moveTo(cx, cy + 3); g.lineTo(cx + 4, cy - 3); g.lineTo(cx - 4, cy - 3); }
         g.endFill();
      }
      // Caps icon: circle + script "C" stroke (Nuka cap).
      public static function iconCaps(g:Graphics, x:Number, y:Number, s:Number, color:uint):void
      {
         var r:Number = s / 2;
         g.lineStyle(1.4, color, 1); g.drawCircle(x + r, y + r, r);
         g.moveTo(x + r + r * 0.5, y + r * 0.55); g.curveTo(x + r * 0.35, y + r * 0.2, x + r * 0.35, y + r);
         g.curveTo(x + r * 0.35, y + s - r * 0.2, x + r + r * 0.5, y + s - r * 0.55);
         g.lineStyle();
      }
      // Weight icon: backpack silhouette.
      public static function iconWeight(g:Graphics, x:Number, y:Number, s:Number, color:uint):void
      {
         g.lineStyle(1.4, color, 1);
         g.drawRoundRect(x + 1, y + 3, s - 2, s - 3, 3, 3);           // body
         g.moveTo(x + s * 0.35, y + 3); g.curveTo(x + s / 2, y - 2, x + s * 0.65, y + 3);  // top handle
         g.moveTo(x + s * 0.28, y + s * 0.55); g.lineTo(x + s * 0.72, y + s * 0.55);        // pocket line
         g.lineStyle();
      }

      // Corner-bracket accent used on active panels/cards.
      public static function brackets(g:Graphics, x:Number, y:Number, w:Number, h:Number, len:Number, color:uint, alpha:Number):void
      {
         g.lineStyle(1.5, color, alpha);
         // TL
         g.moveTo(x, y + len); g.lineTo(x, y); g.lineTo(x + len, y);
         // TR
         g.moveTo(x + w - len, y); g.lineTo(x + w, y); g.lineTo(x + w, y + len);
         // BL
         g.moveTo(x, y + h - len); g.lineTo(x, y + h); g.lineTo(x + len, y + h);
         // BR
         g.moveTo(x + w - len, y + h); g.lineTo(x + w, y + h); g.lineTo(x + w, y + h - len);
         g.lineStyle();
      }

      // 0.0.58 ARTIFACT-PROOF RECT OUTLINE: four FILLED 1px rects instead of a lineStyle stroke. In-game GFx
      // emits stray segments from the stale pen position into stroked primitives (the diagonal-line artifacts;
      // Ruffle never reproduces it, and even pen-parking moveTo did not fully kill it in the field). Fills never
      // touch the line-pen path, so this cannot stray. Use on any REDRAWN-per-render outline.
      public static function frameRect(g:Graphics, x:Number, y:Number, w:Number, h:Number, color:uint, alpha:Number, th:Number = 1):void
      {
         g.beginFill(color, alpha);
         g.drawRect(x, y, w, th);                 // top
         g.drawRect(x, y + h - th, w, th);        // bottom
         g.drawRect(x, y + th, th, h - 2 * th);   // left
         g.drawRect(x + w - th, y + th, th, h - 2 * th);   // right
         g.endFill();
      }

      // 0.0.59 ARTIFACT-PROOF DIAGONAL: a FILLED thin quad between two points instead of a lineStyle stroke.
      // Same rationale as frameRect -- the fill path never touches the line pen, so it cannot emit the stray
      // fan segments the limb-connector strokes produced in-game. moveTo/lineTo here define the FILL path only
      // (no lineStyle is ever set), which the inventory-window fills already proved clean in the field.
      public static function fillLine(g:Graphics, x0:Number, y0:Number, x1:Number, y1:Number, color:uint, alpha:Number, th:Number = 1):void
      {
         var dx:Number = x1 - x0, dy:Number = y1 - y0;
         var len:Number = Math.sqrt(dx * dx + dy * dy);
         if (len < 0.01) { return; }
         var nx:Number = (-dy / len) * (th / 2), ny:Number = (dx / len) * (th / 2);
         g.lineStyle();   // belt: guarantee NO stroke is active for this path
         g.beginFill(color, alpha);
         g.moveTo(x0 + nx, y0 + ny); g.lineTo(x1 + nx, y1 + ny);
         g.lineTo(x1 - nx, y1 - ny); g.lineTo(x0 - nx, y0 - ny);
         g.endFill();
      }

      // 0.0.59: display-sanitize an externally-supplied tab label (PipboyTabs inis can carry glyphs outside the
      // embedded PipOSFont range U+0020-007E / 00A0-00FF -- those render as notdef squares). Keeps chars the font
      // actually has, uppercases for the strip look, and falls back to a placeholder so the tab stays clickable.
      public static function tabLabel(raw:String, slot:int):String
      {
         if (raw == null) { return "TAB " + slot; }
         var up:String = raw.toUpperCase(); var out:String = "";
         for (var i:int = 0; i < up.length; i++) {
            var c:Number = up.charCodeAt(i);
            if ((c >= 0x20 && c <= 0x7E) || (c >= 0xA0 && c <= 0xFF)) { out += up.charAt(i); }
         }
         // trim
         while (out.length > 0 && out.charAt(0) == " ") { out = out.substr(1); }
         while (out.length > 0 && out.charAt(out.length - 1) == " ") { out = out.substr(0, out.length - 1); }
         return (out.length > 0) ? out : ("TAB " + slot);
      }

      // Bottom button-prompt bar (mockup .keybar), PER PAGE. Each page passes ONLY the prompts wired to its own
      // real actions (its BSButtonHintData set) + a universal ESC BACK, so no page shows a dead/foreign prompt
      // ("every element has purpose"). entries = Array of { key:String, label:String }. Builds a self-contained
      // Sprite (boxed bright key + dim label per entry), centers it on the content area, seats it at yTop, and
      // returns it. MUST be called from an on-stage build window (creates TextFields) -- never a tick/handler.
      public static function keybar(host:Sprite, entries:Array, yTop:Number):Sprite
      {
         var bar:Sprite = new Sprite(); bar.mouseEnabled = false; bar.mouseChildren = false; host.addChild(bar);
         var g:Graphics = bar.graphics;
         var pad:Number = 5, boxH:Number = 17, gap:Number = 6, space:Number = 20, x:Number = 0;
         for (var i:int = 0; i < entries.length; i++) {
            var e:Object = entries[i];
            var kt:TextField = mk(bar, 11, PHOS_BRIGHT, true); kt.x = x + pad; kt.y = 2; setText(kt, String(e.key));
            var bw:Number = kt.width + pad * 2;
            g.lineStyle(1, LINE, 0.45); g.drawRoundRect(x, 0, bw, boxH, 3, 3); g.lineStyle();
            var lt:TextField = mk(bar, 11, PHOS_DIM, true); lt.x = x + bw + gap; lt.y = 2; setText(lt, String(e.label));
            x = lt.x + lt.width + space;
         }
         var totalW:Number = x - space;   // drop the trailing inter-entry gap
         // 0.0.58: 15% larger for readability (container transform -- crash-law-safe), centered on scaled width.
         bar.scaleX = 1.15; bar.scaleY = 1.15;
         bar.x = (CX + CR) / 2 - (totalW * 1.15) / 2;
         bar.y = yTop;
         return bar;
      }
   }
}
