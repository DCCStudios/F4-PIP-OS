package pipos
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.text.TextField;
   import flash.text.TextFormat;

   // G10 INSTRUMENTATION (round 12). Toggleable on-screen debug overlay + data-shape dump so the user
   // can screenshot GROUND TRUTH for G2/G3/G4/G5/G6/G7. ENABLED=true in 0.0.6 test builds.
   // Each page: var _dbg = new Debug("STAT"); addChild(_dbg);  then call mark()/input()/pageTab()/dump().
   public class Debug extends Sprite
   {
      public static const ENABLED:Boolean = true;   // master gate: keep TRUE so the backtick data dump works
      // P2-B: the persistent yellow status line was on-screen every frame in normal use. Gate ONLY that line
      // here (default OFF => clean screen); the backtick (192) data-dump stays available for investigations.
      // 0.0.25: temporarily ENABLED for the P0-B mouse-routing field test. 0.0.27: mouse routing CONFIRMED
      // working in game + the InvPage diagnostic retired, so the persistent yellow line is OFF again. ENABLED
      // stays TRUE so the backtick (192) data dump -- now including the _cardInfo card dump -- still works.
      public static const SHOW_STATUS_LINE:Boolean = false;
      public static const DUMP_KEY:uint = 192;       // backtick ` toggles the data dump

      private var _tag:String;
      private var _line:TextField;   // status line (bottom)
      private var _dumpTf:TextField; // data-shape dump (left)
      private var _marks:String = "";
      private var _changeN:int = 0;
      private var _lastInput:String = "-";
      private var _pt:String = "-/-";
      private var _dumpOn:Boolean = false;

      public function Debug(tag:String)
      {
         super();
         this._tag = tag;
         this.mouseEnabled = false; this.mouseChildren = false;
         if (!ENABLED) { this.visible = false; return; }
         // Defer field creation to on-stage: setting .width on an embedded-font field off-stage crashes
         // (FindFont NULL) - the page ctor is off-stage during ProcessLoadQueue.
         addEventListener(Event.ADDED_TO_STAGE, this.onDbgStage);
      }

      private function onDbgStage(e:Event):void
      {
         removeEventListener(Event.ADDED_TO_STAGE, this.onDbgStage);
         if (this._dumpTf != null) { return; }
         // P2-B: only build the yellow status line when explicitly enabled (fresh field width set once == safe).
         if (SHOW_STATUS_LINE) { this._line = this.mk(10, 0xFFE066); addChild(this._line); this._line.width = 876; this._line.x = 4; this._line.y = 684; }
         this._dumpTf = this.mk(10, 0x66FFCC); addChild(this._dumpTf); this._dumpTf.width = 470; this._dumpTf.height = 560; this._dumpTf.multiline = true; this._dumpTf.wordWrap = true;
         this._dumpTf.x = 210; this._dumpTf.y = 96; this._dumpTf.visible = false;
         this._dumpTf.background = true; this._dumpTf.backgroundColor = 0x000000; this._dumpTf.alpha = 0.92;
         this.mark("ctor");
      }

      private function mk(size:int, color:uint):TextField
      {
         // MUST use the embedded Arimo (Theme.tf) - device fonts render nothing under GFx.
         var t:TextField = Theme.tf(size, color, true, "left");
         t.autoSize = "none"; t.multiline = true; t.wordWrap = true;
         return t;
      }

      public function mark(m:String):void { if (!ENABLED) return; this._marks += (this._marks.length ? ">" : "") + m; this.render(); }
      public function change():void { if (!ENABLED) return; this._changeN++; this.render(); }
      public function pageTab(p:*, t:*):void { if (!ENABLED) return; this._pt = String(p) + "/" + String(t); this.render(); }
      public function input(kind:String, code:*, target:*):void
      {
         if (!ENABLED) return;
         var tn:String = "-"; try { tn = (target != null && target.name != null) ? String(target.name) : String(target); } catch (e:*) {}
         this._lastInput = kind + ":" + String(code) + "@" + tn;
         this.render();
      }

      private function render():void
      {
         if (!ENABLED || this._line == null) return;
         var focusN:String = "-"; try { if (stage != null && stage.focus != null) { focusN = (stage.focus.name != null) ? String(stage.focus.name) : "obj"; } } catch (e:*) {}
         this._line.text = Theme.sanitize("[" + this._tag + "] pt=" + this._pt + " life=" + this._marks + " chg#" + this._changeN +
                           " in=" + this._lastInput + " focus=" + focusN);
      }

      // Toggle + fill the data-shape dump. Call from a page on DUMP_KEY with the arrays you care about.
      public function toggleDump():Boolean { if (!ENABLED) return false; this._dumpOn = !this._dumpOn; this._dumpTf.visible = this._dumpOn; return this._dumpOn; }
      public function isDumpKey(code:uint):Boolean { return code == DUMP_KEY; }

      public function dump(label:String, obj:*):void
      {
         if (!ENABLED || this._dumpTf == null || !this._dumpOn) return;
         var s:String = "== " + label + " ==\n";
         if (obj == null) { s += "(null)\n"; }
         else {
            var n:int = 0;
            for (var k:String in obj) { var v:*; try { v = obj[k]; } catch (e:*) { v = "?"; } s += k + " = " + String(v) + "\n"; if (++n > 40) { s += "...\n"; break; } }
            if (n == 0) { s += "(no enumerable props; value=" + String(obj) + ")\n"; }
         }
         this._dumpTf.appendText(Theme.sanitize(s));
      }
      public function clearDump():void { if (ENABLED && this._dumpTf != null) this._dumpTf.text = ""; }
   }
}
