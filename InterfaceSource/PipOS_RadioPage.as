package
{
   import Shared.AS3.BSButtonHintData;
   import Shared.BGSExternalInterface;
   import pipos.PipList;
   import pipos.Theme;
   import pipos.Ticker;
   import pipos.Debug;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.geom.Rectangle;
   import flash.text.TextField;

   // PIP-OS Radio page. Stations from DataObj.RadioList; tuning via ToggleRadioStationActiveStatus.
   // Oscilloscope is driven by pipos.Ticker (time-based, getTimer clamp) per the frame-cadence rule:
   // animated waveform while a station is active, flatline + NO SIGNAL when off.
   public class PipOS_RadioPage extends PipboyPage
   {
      private var _title:TextField;
      private var _list:PipList;
      private var _scope:Sprite;
      private var _freq:TextField;
      private var _dj:TextField;
      private var _signal:TextField;
      private var _freqHdr:TextField;    // parity: stations panel header "FREQUENCIES" (mockup .panel h3)
      private var _scopeHdr:TextField;   // parity: scope panel header "OSCILLOSCOPE" (mockup .panel h3)
      private var _lastData:Pipboy_DataObj;
      private var _ticker:Ticker;
      private var _phase:Number = 0;
      private var _activeIdx:int = -1;
      private var _dbg:Debug;
      private var _panels:Array = [];        // panel rects for the DEBUG clearance overlay

      // 16:9 grid (mockup RADIO: 1fr(750) stations | 560 scope, gap16). Derived from Theme.mx/ms.
      // Mockup: the OSCILLOSCOPE is ONE panel filling the right column, with the #freqrow (freq + station) at its
      // BOTTOM edge -- not a separate lower panel. We match that: single full-height panel, trace above, freqrow band below.
      private var SCOPE_X:Number = Theme.mx(1006);  // 604.8 scope column left
      private var SCOPE_Y:Number = Theme.BY;        // 113.6 top of grid
      private var SCOPE_W:Number = Theme.ms(560);   // 448   scope column width
      private const SCOPE_HDR:Number = 22;          // header band reserved at the scope panel top (OSCILLOSCOPE)
      private const FREQ_STRIP:Number = 54;         // freqrow band at the panel bottom (freq readout + station + signal)

      private var _tune:BSButtonHintData;

      public function PipOS_RadioPage()
      {
         super();
         _TabNames = new Array("$PipboyRadioCategory");
         this.buildPanels();
         this._dbg = new Debug("RADIO"); addChild(this._dbg);
         Theme.life("RA.c");   // 0.0.52 forensics (also traces how far radio gets if its crash recurs)
      }

      override protected function PopulateButtonHintData():*
      {
         this._tune = new BSButtonHintData("TUNE","Enter","PSN_A","Xenon_A",1,this.doTune);
         _buttonHintDataV.push(this._tune);
      }

      override protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.Radio; }
      private function sfx(ev:String):void { BGSExternalInterface.call(this.codeObj, "PlaySound", ev); }

      // Scope trace interior height: from below the header band down to the freqrow strip.
      private function scopeTraceH():Number { return (Theme.BB - this.FREQ_STRIP) - (this.SCOPE_Y + Theme.PAD + this.SCOPE_HDR); }

      private function buildPanels():void
      {
         Theme.life("RA.p0");
         var P:Number = Theme.PAD;
         var stationsW:Number = Theme.ms(750);   // 600  stations column width
         var g:* = this.graphics;
         Theme.panelR(g, this._panels, Theme.CX, Theme.BY, stationsW, Theme.BB - Theme.BY);
         // ONE oscilloscope panel filling the right column (trace above, freqrow band at the bottom).
         Theme.panelR(g, this._panels, this.SCOPE_X, this.SCOPE_Y, this.SCOPE_W, Theme.BB - this.SCOPE_Y, 0.5);
         // Divider above the freqrow band (mockup #freqrow border-top).
         var fy:Number = Theme.BB - this.FREQ_STRIP;
         g.lineStyle(1, Theme.LINE, 0.16); g.moveTo(this.SCOPE_X + P, fy); g.lineTo(this.SCOPE_X + this.SCOPE_W - P, fy); g.lineStyle();
         this._list = new PipList(stationsW - 2 * P, 28, 18);   // 18 rows: a header band (FREQUENCIES, mockup h3) is reserved above
         this._list.x = Theme.CX + P; this._list.y = Theme.BY + 34; this._list.onSelectionChange = this.onListSel; this._list.onItemPress = this.onListPress; this._list.playSound = this.sfx; addChild(this._list);
         // Scope trace is inset below the OSCILLOSCOPE header band (SCOPE_HDR) and above the freqrow strip; onTick uses scopeTraceH().
         this._scope = new Sprite(); this._scope.x = this.SCOPE_X + P; this._scope.y = this.SCOPE_Y + P + this.SCOPE_HDR; this._scope.scrollRect = new Rectangle(0, 0, this.SCOPE_W - 2 * P, this.scopeTraceH()); addChild(this._scope);
         addEventListener(Event.ADDED_TO_STAGE, this.onSelfStage);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onSelfUnstage);
         this.onTick(0);
      }

      private function buildText():void
      {
         Theme.life("RA.t0");
         var P:Number = Theme.PAD;
         // No standalone page title (mockup: the sidebar shows the active page). Keep the pooled field, hidden.
         this._title = Theme.mk(this, 22, Theme.PHOS_BRIGHT, true); this._title.visible = false; Theme.setText(this._title, "RADIO");
         Theme.life("RA.t1");   // first field created + text set (font resolved if we got past this)
         // Parity: panel headers (mockup #page-radio h3s). POOLED, static, geometry-before-text; never re-texted.
         this._freqHdr = Theme.mk(this, 12, Theme.PHOS_BRIGHT, true); this._freqHdr.x = Theme.CX + P; this._freqHdr.y = Theme.BY + 8;   // 0.0.46: bright panel heading (mockup)
         var fhf:* = this._freqHdr.defaultTextFormat; fhf.letterSpacing = 1.4; this._freqHdr.defaultTextFormat = fhf; Theme.setText(this._freqHdr, "FREQUENCIES");
         this._scopeHdr = Theme.mk(this, 12, Theme.PHOS_BRIGHT, true); this._scopeHdr.x = this.SCOPE_X + P; this._scopeHdr.y = this.SCOPE_Y + P;   // 0.0.46: bright panel heading (mockup)
         var shf:* = this._scopeHdr.defaultTextFormat; shf.letterSpacing = 1.4; this._scopeHdr.defaultTextFormat = shf; Theme.setText(this._scopeHdr, "OSCILLOSCOPE");
         // Parity #freqrow (mockup): a single band at the panel BOTTOM -- big MHz readout on the LEFT, station name
         // + SIGNAL on the RIGHT (baseline-aligned). Right fields are FIXED autoSize="none" right boxes (refresh =
         // setText only). freq flavor: stationMHz (docs/FunctionalitySpec.md).
         var stripTop:Number = Theme.BB - this.FREQ_STRIP;
         var rW:Number = this.SCOPE_W - 2 * P;
         this._freq = Theme.mk(this, 24, Theme.PHOS_BRIGHT, true); this._freq.x = this.SCOPE_X + P + 2; this._freq.y = stripTop + 8;
         var frf:* = this._freq.defaultTextFormat; frf.letterSpacing = 0.6; this._freq.defaultTextFormat = frf;
         Theme.life("RA.t2");   // entering the fixed-width right-aligned fields (.width writes = FindFont hot zone)
         this._dj = Theme.mk(this, 13, Theme.PHOS, false, "right"); this._dj.autoSize = "none"; this._dj.width = rW - 100; this._dj.height = 16; this._dj.x = this.SCOPE_X + P; this._dj.y = stripTop + 15;
         this._signal = Theme.mk(this, 11, Theme.PHOS_DIM, true, "right"); this._signal.autoSize = "none"; this._signal.width = rW - 100; this._signal.height = 14; this._signal.x = this.SCOPE_X + P; this._signal.y = stripTop + 33; var sgf:* = this._signal.defaultTextFormat; sgf.letterSpacing = 1.2; this._signal.defaultTextFormat = sgf; Theme.setText(this._signal, "SIGNAL -");
         // Lazy-build cleanup (mirrors InvPage A2): force the PipList pool build NOW in the on-stage window so a
         // first render() can never fire from an interaction path (onWheel/handleKey) later.
         if (this._list != null && stage != null) { this._list.render(); }
         // 0.0.57: keybar restored (see InvPage note).
         Theme.keybar(this, [{key:"ESC",label:"BACK"},{key:"ENTER",label:"TUNE"},{key:"T",label:"PERK CHART"}], Theme.my(858));
         Theme.life("RA.t3");   // buildText completed
      }

      private var _textBuilt:Boolean = false;
      private function ensureText():void { if (this._textBuilt || stage == null) { return; } this._textBuilt = true; this.buildText(); }

      private function onSelfStage(e:Event):void
      {
         Theme.life("RA.s");
         this.ensureText();
         if (this._ticker == null) { this._ticker = new Ticker(this, this.onTick); }
         this._ticker.start();
         if (stage != null) { stage.addEventListener(KeyboardEvent.KEY_DOWN, this.onKey); }
      }
      private function onSelfUnstage(e:Event):void
      {
         if (this._ticker != null) { this._ticker.stop(); }
         if (stage != null) { stage.removeEventListener(KeyboardEvent.KEY_DOWN, this.onKey); }
      }

      private var _lifeEvt:Boolean = false;
      override protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void
      {
         super.onPipboyChangeEvent(param1);
         if (!this._lifeEvt) { this._lifeEvt = true; Theme.life("RA.e"); }
         this.ensureText(); if (!this._textBuilt) { return; }
         var d:Pipboy_DataObj = param1.DataObj; this._lastData = d; if (this._dbg != null) { this._dbg.change(); this._dbg.pageTab(d.CurrentPage, d.CurrentTab); }
         this._list.setItems(d.RadioList, this.radioAdapter);
         this._activeIdx = -1;
         var arr:Array = d.RadioList;
         if (arr != null) { for (var i:int = 0; i < arr.length; i++) { if (arr[i] != null && arr[i].active == true) { this._activeIdx = i; break; } } }
         this.renderInfo();
         SetIsDirty();
      }

      private function radioAdapter(e:Object):Object
      {
         // P2-D: the active station was flagged legendary -> Theme.sparkle drew a stray amber triangle glyph
         // next to the selected row. The "ON AIR" right-text already conveys active; drop the sparkle marker.
         return { label:(e!=null&&e.text!=null?String(e.text):""), right:(e!=null&&e.active==true?"ON AIR":""), star:false, legendary:false, dim:false };
      }

      // AUDIT (0.0.31, crash class (2)): renderInfo / onListSel / doTune / onTick are already UPDATE-ONLY --
      // _freq/_dj/_signal are pooled in buildText and only receive setText/textColor here; the scope is pure
      // graphics; the station list is the (now pooled) PipList. No field creation or geometry write on any
      // interaction-reachable path, so no conversion was required beyond the shared PipList/Theme fixes.
      private function renderInfo():void
      {
         if (this._freq == null) { return; }
         var arr:Array = this._lastData ? this._lastData.RadioList : null;
         var sel:int = this._list.selectedIndex;
         var e:Object = (arr != null && sel >= 0 && sel < arr.length) ? arr[sel] : null;
         var nm:String = (e != null && e.text != null) ? String(e.text) : "";
         // #freqrow: large MHz readout (flavor) over the real station NAME. No DJ is fabricated (not in engine data).
         Theme.setText(this._freq, (nm.length > 0) ? this.stationMHz(nm) : "— MHz");
         Theme.setText(this._dj, nm);
         var recep:Number = (e != null && e.reception != null) ? Number(e.reception) : -1;
         Theme.setText(this._signal, (recep >= 0) ? ("SIGNAL " + Math.round(recep * 100) + "%") : ((e != null && e.active == true) ? "ON AIR" : "SIGNAL -"));
      }

      // FLAVOR (documented in docs/FunctionalitySpec.md): FO4 radio stations expose NO real carrier frequency, so
      // the MHz shown in #freqrow is a display-only pseudo-frequency DERIVED from the station NAME. It is STABLE +
      // DETERMINISTIC: the same station name always yields the same number. Known vanilla stations are pinned to
      // their mockup values; any other (modded) station hashes its name into the US FM band (87.9-107.9 MHz, 0.2
      // steps). Pure string derivation -- no TextField access (gated update-only by ctor_text_check).
      private function stationMHz(name:String):String
      {
         var key:String = name.toUpperCase();
         if (key.indexOf("DIAMOND CITY") >= 0) { return "102.5 MHz"; }
         if (key.indexOf("CLASSICAL") >= 0) { return "98.7 MHz"; }
         if (key.indexOf("FREEDOM") >= 0 || key.indexOf("MINUTEMEN") >= 0) { return "94.3 MHz"; }
         if (key.indexOf("VAULT 111") >= 0 || key.indexOf("DISTRESS") >= 0) { return "87.1 MHz"; }
         var hash:int = 0;
         for (var i:int = 0; i < name.length; i++) { hash = (hash * 31 + name.charCodeAt(i)) & 0x7fffffff; }
         var tenths:int = 879 + (hash % 101) * 2;   // 879..1079 -> 87.9..107.9 MHz in 0.2 (2-tenths) steps
         return (int(tenths / 10)) + "." + (tenths % 10) + " MHz";
      }

      private function onTick(dt:Number):void
      {
         this._phase += dt * 3.0;   // time-based drift; independent of frame rate
         var g:* = this._scope.graphics; g.clear();
         var w:Number = this.SCOPE_W - 2 * Theme.PAD;   // draw within the PAD-inset scope interior
         var h:Number = this.scopeTraceH();             // header band reserved above, freqrow band below
         // Scope face (mockup canvas fill #0a120c).
         g.beginFill(0x0A120C, 1); g.drawRect(0, 0, w, h); g.endFill();
         // Faint phosphor graticule (mockup: rgba(134,224,140,.08); 24px CSS grid -> ~19 local at MS=0.8).
         var step:Number = 19;
         g.lineStyle(1, Theme.PHOS, 0.08);
         for (var gx:Number = 0; gx <= w + 0.5; gx += step) { g.moveTo(gx, 0); g.lineTo(gx, h); }
         for (var gy2:Number = 0; gy2 <= h + 0.5; gy2 += step) { g.moveTo(0, gy2); g.lineTo(w, gy2); }
         g.lineStyle();
         var midY:Number = h / 2;
         var maxA:Number = midY - 3;                    // keep the trace off the top/bottom edges
         var on:Boolean = (this._activeIdx >= 0);
         // Waveform: compound-harmonic sine (mockup drawScope: sin*.5 + sin(2.7)*.3 + sin(6.1)*.12), amp v*h*0.3.
         g.lineStyle(1.6, on ? Theme.PHOS_BRIGHT : Theme.PHOS_DIM, on ? 1 : 0.5);
         g.moveTo(0, midY);
         if (on)
         {
            for (var x:Number = 0; x <= w; x += 4)
            {
               var ph:Number = this._phase + x / 27;
               var v:Number = Math.sin(ph) * 0.5 + Math.sin(ph * 2.7) * 0.3 + Math.sin(ph * 6.1) * 0.12;
               var amp:Number = v * h * 0.3;
               if (amp > maxA) { amp = maxA; } else if (amp < -maxA) { amp = -maxA; }
               g.lineTo(x, midY + amp);
            }
         }
         else { g.lineTo(w, midY); }   // flatline
         g.lineStyle();
      }

      public function debugRects():Array { return this._panels; }
      private function onListSel(i:int):void { this.renderInfo(); }
      private function onListPress(i:int):void { this.doTune(); }

      private function doTune():void
      {
         // P1/C5: vanilla passes selectedEntry.frequency (a Number), NOT the list index. Passing an
         // index made the native side mis-lookup the station -> CTD on tune (W6 single-click detonated it).
         var i:int = this._list.selectedIndex; if (i < 0) { return; }
         var arr:Array = this._lastData ? this._lastData.RadioList : null;
         var st:Object = (arr != null && i < arr.length) ? arr[i] : null;
         if (st == null) { return; }
         this.sfx((st.active == true) ? "UIMenuCancel" : "UIMenuOK");
         BGSExternalInterface.call(this.codeObj, "ToggleRadioStationActiveStatus", st.frequency);
      }

      // Raw KEY_DOWN drives ONLY station-list navigation. Tune is the single Accept path (keyboard
      // Enter / gamepad A); mouse click on the selected station also tunes (onItemPress).
      private function onKey(e:KeyboardEvent):void {
         if (this._dbg != null) {
            this._dbg.input("key", e.keyCode, e.target);
            if (this._dbg.isDumpKey(e.keyCode)) {
               this._dbg.clearDump(); this._dbg.toggleDump();
               if (this._lastData != null) { this._dbg.dump("RadioList[0]", (this._lastData.RadioList != null && this._lastData.RadioList.length > 0) ? this._lastData.RadioList[0] : null); }
               return;
            }
         }
         this._list.handleKey(e.keyCode);
      }

      override public function ProcessUserEvent(param1:String, param2:Boolean):Boolean
      {
         if (!param2 && param1 == "Accept") { this.doTune(); return true; }   // Enter / Xenon_A
         return false;
      }
   }
}
