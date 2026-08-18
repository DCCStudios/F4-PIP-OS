package
{
   import Shared.AS3.BSButtonHintData;
   import Shared.BGSExternalInterface;
   import pipos.PipList;
   import pipos.Theme;
   import pipos.VaultBoy;
   import pipos.Debug;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.text.TextFormat;

   // PIP-OS Stats page (custom replacement for the vanilla stock Stats page), laid out to the M1 mockup
   // (Previews/reference/mockup-stat*.png). Three sub-tabs:
   //   STATUS  -- HP/AP/RADS meters (open, per-meter frames, no containing panel), SPECIAL tiles directly
   //              under the meters (no heading/panel), floating figure with anatomical limb-condition chips,
   //              a top-right LEVEL bar, and an ACTIVE EFFECTS panel (EFFECT | SOURCE).
   //   SPECIAL -- attribute list (ATTRIBUTE | VALUE) + a selected-attribute description panel.
   //   PERKS   -- perk list (PERK / EFFECT | RANK) + a selected-perk description panel.
   // Vanilla plumbing preserved: UseStimpak / UseRadaway, onNewTab, ConditionClips Vault Boy (pipos.VaultBoy),
   // SPECIALList / PerksList / ActiveEffects / CurrHP.. / XPLevel reads. Single input path per action.
   //
   // CRASH LAW (0.0.41): ctor -> buildPanels (font-free: Sprites + graphics only, NO TextField). ALL TextFields
   // are created ONCE with baked geometry in buildText (on-stage, via ensureText). Every render/handler is
   // UPDATE-ONLY: setText / textColor / visible + Shape graphics (bars, frames, chips, panel borders redraw
   // freely -- they are not TextField geometry writes). No field creation or TextField geometry write on any
   // data/interaction/tick path. Gated by tools/ctor_text_check.py (StatsPage now in its lists).
   public class PipOS_StatsPage extends PipboyPage
   {
      // [label, chipCenterX, chipCenterY, targetX, targetY, conditionIndex]  (content-local coords)
      private const LIMBS:Array = [
         ["HEAD",  500, 144, 500, 190, 0],
         ["L ARM", 344, 262, 452, 280, 1],
         ["R ARM", 656, 262, 548, 280, 2],
         ["L LEG", 356, 424, 470, 412, 4],
         ["R LEG", 644, 424, 530, 412, 5],
         ["TORSO", 500, 636, 500, 582, 3]
      ];
      private const SPEC:Array = ["STR","PER","END","CHA","INT","AGI","LCK"];

      // Layout constants (content-local units; Theme.CX/BY/BB/CR frame the content band).
      private const LEFTW:Number = 260;        // meters + SPECIAL-tiles column width
      private const METER_PITCH:Number = 56;
      private const METER_H:Number = 46;
      private const TILE_W:Number = 33;
      private const TILE_GAP:Number = 4;
      private const TILE_H:Number = 44;
      private const FIGX:Number = 500;          // figure centre X
      private const EFX:Number = 746;           // ACTIVE EFFECTS panel left
      private const LPW:Number = 708;           // SPECIAL/PERKS list-panel width
      private const CHIPW:Number = 64;
      private const CHIPH:Number = 28;
      private const EF_ROWS:int = 8;            // pooled ACTIVE EFFECTS rows

      private var _title:TextField;
      private var _subtabs:Sprite;
      private var _subFields:Array = [];
      private var _subUL:Array = [];

      private var _status:Sprite;
      private var _meters:Sprite;
      private var _special:Sprite;
      private var _figure:Sprite;
      private var _vb:VaultBoy;
      private var _limbs:Sprite;
      private var _effects:Sprite;
      private var _levelBox:Sprite;

      private var _list:PipList;                // SPECIAL / PERKS list
      private var _listPanel:Sprite;            // list-panel border + h3 + column headers
      private var _descPanel:Sprite;            // description-panel border + h3 + body

      // Pooled STATUS fields
      private var _mLabel:Array = [];           // HP/AP/RADS labels
      private var _mVal:Array = [];             // HP/AP/RADS values
      private var _spVal:Array = [];            // 7 SPECIAL tile values
      private var _spLbl:Array = [];            // 7 SPECIAL tile labels
      private var _limbName:Array = [];         // 6 limb-chip names
      private var _limbHits:Array = [];         // 6 limb-chip hit sprites (stimpak targets)
      private var _lvLabel:TextField;           // "LEVEL"
      private var _lvNum:TextField;             // level number
      private var _efHead:TextField;            // "ACTIVE EFFECTS"
      private var _efColL:TextField;            // "EFFECT"
      private var _efColR:TextField;            // "SOURCE"
      private var _efRowL:Array = [];           // effect rows: effect text (left)
      private var _efRowR:Array = [];           // effect rows: source text (right)
      // Pooled SPECIAL/PERKS fields
      private var _listH3:TextField;            // "S.P.E.C.I.A.L." / "PERKS"
      private var _listColL:TextField;          // "ATTRIBUTE" / "PERK / EFFECT"
      private var _listColR:TextField;          // "VALUE" / "RANK"
      private var _descH3:TextField;            // selected attribute/perk name
      private var _descBody:TextField;          // selected description

      private var _curTab:int = -1;
      private var _showVaultBoy:Boolean = true;
      private var _lastData:Pipboy_DataObj;
      private var _dbg:Debug;
      private var _panels:Array = [];

      private var _stim:BSButtonHintData;
      private var _rad:BSButtonHintData;
      private var _vbtn:BSButtonHintData;

      public function PipOS_StatsPage()
      {
         super();
         Theme.life("ST.c");   // 0.0.52 forensics: ctor entered (document class constructed)
         _TabNames = new Array("$PipboyConditionCategory","$PipboySPECIALCategory","$PipboyPerksCategory");
         this.buildPanels();
         this._dbg = new Debug("STAT"); addChild(this._dbg);
         Theme.life("ST.c1");  // ctor completed
      }

      override protected function PopulateButtonHintData():*
      {
         this._stim = new BSButtonHintData("STIMPAK","E","PSN_A","Xenon_A",1,this.doStim);
         this._rad  = new BSButtonHintData("RADAWAY","R","PSN_X","Xenon_X",1,this.doRad);
         this._vbtn = new BSButtonHintData("VAULT BOY","V","PSN_L1","Xenon_L1",1,this.doToggleFigure);
         _buttonHintDataV.push(this._stim); _buttonHintDataV.push(this._rad); _buttonHintDataV.push(this._vbtn);
      }

      override protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.Stats; }
      private function sfx(ev:String):void { BGSExternalInterface.call(this.codeObj, "PlaySound", ev); }

      // CTOR (font-free): Sprites + graphics + PipList + VaultBoy + hit sprites ONLY. No TextField.
      private function buildPanels():void
      {
         Theme.life("ST.p0");
         var P:Number = Theme.PAD;
         this._subtabs = new Sprite(); this._subtabs.y = Theme.SUB_Y; addChild(this._subtabs);

         this._status = new Sprite(); addChild(this._status);
         this._meters = new Sprite(); this._status.addChild(this._meters);
         this._special = new Sprite(); this._status.addChild(this._special);
         this._figure = new Sprite(); this._status.addChild(this._figure);
         try { this._vb = new VaultBoy(300); this._vb.x = this.FIGX; this._vb.y = 250; this._figure.addChild(this._vb); } catch (e:Error) { this._vb = null; }
         Theme.life("ST.p1");   // VaultBoy constructed (or caught)
         this._limbs = new Sprite(); this._status.addChild(this._limbs);
         // limb-chip hit sprites (fixed positions; stimpak targets). Font-free.
         this._limbHits = [];
         for (var i:int = 0; i < LIMBS.length; i++) {
            var L:Array = LIMBS[i]; var cx:Number = Number(L[1]), cy:Number = Number(L[2]);
            var hit:Sprite = new Sprite(); hit.graphics.beginFill(0x000000, 0.004); hit.graphics.drawRect(cx - CHIPW / 2, cy - CHIPH / 2, CHIPW, CHIPH); hit.graphics.endFill();
            hit.buttonMode = true; hit.addEventListener(MouseEvent.CLICK, this.onLimbClick); this._limbs.addChild(hit); this._limbHits.push(hit);
         }
         this._effects = new Sprite(); this._effects.x = this.EFX; this._effects.y = Theme.BY; this._status.addChild(this._effects);

         this._levelBox = new Sprite(); addChild(this._levelBox);   // top-right LEVEL bar (all tabs)

         // SPECIAL / PERKS list + description (hidden on STATUS)
         this._listPanel = new Sprite(); this._listPanel.visible = false; addChild(this._listPanel);
         this._list = new PipList(this.LPW - 2 * P, 27, 18);
         this._list.x = Theme.CX + P; this._list.y = Theme.BY + 52;
         this._list.onSelectionChange = this.onListSel; this._list.playSound = this.sfx; this._list.visible = false; addChild(this._list);
         this._descPanel = new Sprite(); this._descPanel.visible = false; addChild(this._descPanel);

         addEventListener(Event.ADDED_TO_STAGE, this.onPageStage);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onPageUnstage);
         Theme.life("ST.p2");   // buildPanels completed
      }

      // ALL TextField creation + baked geometry (on-stage, via ensureText). Geometry-before-text throughout.
      private function buildText():void
      {
         Theme.life("ST.t0");
         var P:Number = Theme.PAD;
         this._title = Theme.mk(this, 22, Theme.PHOS_BRIGHT, true); this._title.visible = false; Theme.setText(this._title, "STATUS");
         this.buildSubtabs();

         // ----- STATUS meters (HP/AP/RADS): label + right-aligned value; frame + bar are graphics -----
         var mNames:Array = ["HP", "AP", "RADS"];
         for (var mi:int = 0; mi < 3; mi++) {
            var my0:Number = Theme.BY + mi * METER_PITCH;
            var ml:TextField = Theme.mk(this._meters, 11, Theme.PHOS_DIM, true); ml.x = Theme.CX + 12; ml.y = my0 + 8; Theme.setText(ml, String(mNames[mi])); this._mLabel.push(ml);
            var mv:TextField = Theme.mk(this._meters, 12, Theme.PHOS_BRIGHT, true, "right"); mv.autoSize = "none"; mv.width = LEFTW - 24; mv.height = 16; mv.x = Theme.CX + 12; mv.y = my0 + 7; Theme.setText(mv, "- / -"); this._mVal.push(mv);
         }
         // ----- SPECIAL tiles (7): value (big, centre) + label (small, centre); frame is graphics -----
         var tileY:Number = Theme.BY + 3 * METER_PITCH + 14;
         var tileX0:Number = Theme.CX + (LEFTW - (7 * TILE_W + 6 * TILE_GAP)) / 2;
         for (var si:int = 0; si < 7; si++) {
            var tx:Number = tileX0 + si * (TILE_W + TILE_GAP);
            var sv:TextField = Theme.mk(this._special, 17, Theme.PHOS_BRIGHT, true, "center"); sv.autoSize = "none"; sv.width = TILE_W; sv.height = 22; sv.x = tx; sv.y = tileY + 5; Theme.setText(sv, "-"); this._spVal.push(sv);
            var sl:TextField = Theme.mk(this._special, 7, Theme.PHOS_DIM, true, "center"); sl.autoSize = "none"; sl.width = TILE_W; sl.height = 10; sl.x = tx; sl.y = tileY + TILE_H - 12; Theme.setText(sl, String(SPEC[si])); this._spLbl.push(sl);
         }
         // ----- limb-chip names (6) -----
         for (var li:int = 0; li < LIMBS.length; li++) {
            var LL:Array = LIMBS[li]; var lcx:Number = Number(LL[1]), lcy:Number = Number(LL[2]);
            var ln:TextField = Theme.mk(this._limbs, 9, Theme.PHOS, true, "center"); ln.autoSize = "none"; ln.width = CHIPW; ln.height = 12; ln.x = lcx - CHIPW / 2; ln.y = lcy - CHIPH / 2 + 3; Theme.setText(ln, String(LL[0])); this._limbName.push(ln);
         }
         // ----- LEVEL bar (top-right, all tabs) -----
         this._lvLabel = Theme.mk(this._levelBox, 11, Theme.PHOS_DIM, true); this._lvLabel.x = 0; this._lvLabel.y = 2; var lvf:* = this._lvLabel.defaultTextFormat; lvf.letterSpacing = 1.4; this._lvLabel.defaultTextFormat = lvf; Theme.setText(this._lvLabel, "LEVEL");
         this._lvNum = Theme.mk(this._levelBox, 12, Theme.PHOS_BRIGHT, true); this._lvNum.x = 46; this._lvNum.y = 1; Theme.setText(this._lvNum, "-");
         // ----- ACTIVE EFFECTS panel (children are _effects-local; _effects at (EFX, BY)) -----
         this._efHead = Theme.mk(this._effects, 12, Theme.PHOS_BRIGHT, true); this._efHead.x = P; this._efHead.y = P; var ehf:* = this._efHead.defaultTextFormat; ehf.letterSpacing = 1.4; this._efHead.defaultTextFormat = ehf; Theme.setText(this._efHead, "ACTIVE EFFECTS");   // 0.0.46: bright heading
         var efW:Number = (Theme.CR - EFX) - 2 * P;
         this._efColL = Theme.mk(this._effects, 8, Theme.PHOS_DIM, true); this._efColL.x = P; this._efColL.y = P + 24; Theme.setText(this._efColL, "EFFECT");
         this._efColR = Theme.mk(this._effects, 8, Theme.PHOS_DIM, true, "right"); this._efColR.autoSize = "none"; this._efColR.width = efW; this._efColR.height = 12; this._efColR.x = P; this._efColR.y = P + 24; Theme.setText(this._efColR, "SOURCE");
         for (var ei:int = 0; ei < EF_ROWS; ei++) {
            var ry:Number = P + 46 + ei * 22;
            var el:TextField = Theme.mk(this._effects, 12, Theme.PHOS, false); el.autoSize = "none"; el.width = efW - 74; el.height = 16; el.x = P; el.y = ry; el.visible = false; this._efRowL.push(el);
            var er:TextField = Theme.mk(this._effects, 11, Theme.PHOS_DIM, false, "right"); er.autoSize = "none"; er.width = efW; er.height = 14; er.x = P; er.y = ry + 1; er.visible = false; this._efRowR.push(er);
         }

         // ----- SPECIAL / PERKS list panel (border drawn once; h3 + column headers pooled) -----
         var lpg:* = this._listPanel.graphics;
         lpg.beginFill(Theme.PANEL, 0.82); lpg.drawRoundRect(Theme.CX, Theme.BY, LPW, Theme.BB - Theme.BY, 8, 8); lpg.endFill();
         lpg.lineStyle(1, Theme.LINE, 0.38); lpg.drawRoundRect(Theme.CX + 0.5, Theme.BY + 0.5, LPW - 1, (Theme.BB - Theme.BY) - 1, 8, 8); lpg.lineStyle();
         lpg.lineStyle(1, Theme.LINE, 0.2); lpg.moveTo(Theme.CX + P, Theme.BY + 46); lpg.lineTo(Theme.CX + LPW - P, Theme.BY + 46); lpg.lineStyle();
         this._listH3 = Theme.mk(this._listPanel, 12, Theme.PHOS_BRIGHT, true); this._listH3.x = Theme.CX + P; this._listH3.y = Theme.BY + 8; var lh3f:* = this._listH3.defaultTextFormat; lh3f.letterSpacing = 1.4; this._listH3.defaultTextFormat = lh3f; Theme.setText(this._listH3, "S.P.E.C.I.A.L.");   // 0.0.46: bright heading
         this._listColL = Theme.mk(this._listPanel, 9, Theme.PHOS_DIM, true); this._listColL.x = Theme.CX + P + 12; this._listColL.y = Theme.BY + 30; var lclf:* = this._listColL.defaultTextFormat; lclf.letterSpacing = 1.2; this._listColL.defaultTextFormat = lclf; Theme.setText(this._listColL, "ATTRIBUTE");
         this._listColR = Theme.mk(this._listPanel, 9, Theme.PHOS_DIM, true, "right"); this._listColR.autoSize = "none"; this._listColR.width = LPW - 2 * P - 12; this._listColR.height = 12; this._listColR.x = Theme.CX + P; this._listColR.y = Theme.BY + 30; var lcrf:* = this._listColR.defaultTextFormat; lcrf.letterSpacing = 1.2; this._listColR.defaultTextFormat = lcrf; Theme.setText(this._listColR, "VALUE");

         // ----- SPECIAL / PERKS description panel -----
         var dpx:Number = Theme.CX + LPW + 16;
         var dpw:Number = Theme.CR - dpx;
         var dpg:* = this._descPanel.graphics;
         dpg.beginFill(Theme.PANEL, 0.82); dpg.drawRoundRect(dpx, Theme.BY, dpw, 118, 8, 8); dpg.endFill();
         dpg.lineStyle(1, Theme.LINE, 0.38); dpg.drawRoundRect(dpx + 0.5, Theme.BY + 0.5, dpw - 1, 117, 8, 8); dpg.lineStyle();
         dpg.lineStyle(1, Theme.LINE, 0.2); dpg.moveTo(dpx + P, Theme.BY + 32); dpg.lineTo(dpx + dpw - P, Theme.BY + 32); dpg.lineStyle();
         this._descH3 = Theme.mk(this._descPanel, 12, Theme.PHOS_BRIGHT, true); this._descH3.autoSize = "none"; this._descH3.width = dpw - 2 * P; this._descH3.height = 18; this._descH3.x = dpx + P; this._descH3.y = Theme.BY + 8; var dh3f:* = this._descH3.defaultTextFormat; dh3f.letterSpacing = 1.2; this._descH3.defaultTextFormat = dh3f; Theme.setText(this._descH3, "");
         this._descBody = Theme.mk(this._descPanel, 12, Theme.PHOS_DIM, false); this._descBody.autoSize = "none"; this._descBody.multiline = true; this._descBody.wordWrap = true; this._descBody.width = dpw - 2 * P; this._descBody.height = 72; this._descBody.x = dpx + P; this._descBody.y = Theme.BY + 40; Theme.setText(this._descBody, "");

         // Force the PipList pool build now, inside this proven-safe on-stage window (mirrors Inv/Data A2).
         if (this._list != null && stage != null) { this._list.render(); }
         // Per-page bottom keybar: only STAT's wired actions (STIMPAK / RADAWAY / figure toggle) + ESC BACK.
         // 0.0.57: keybar restored (see InvPage note).
         Theme.keybar(this, [{key:"ESC",label:"BACK"},{key:"E",label:"STIMPAK"},{key:"R",label:"RADAWAY"},{key:"V",label:"VAULT BOY"},{key:"T",label:"PERK CHART"}], Theme.my(858));
         Theme.life("ST.t1");   // buildText completed
      }

      private var _textBuilt:Boolean = false;
      private function ensureText():void { if (this._textBuilt || stage == null) { return; } this._textBuilt = true; this.buildText(); }

      // POOL BUILDER (called once from buildText). Pooled sub-tab labels; active = colour + three-dot indicator.
      // 0.0.50 PIPBOYTABS COMPAT: PipboyTabs (PBT) INJECTS extra sub-tabs into existing pages -- its DLL/SWF pushes
      // tab names onto the CURRENT page's _TabNames (Menu.getChildAt(4)["_TabNames"].push, decompiled PipboyTabs.as
      // L113) and overlays ITS OWN clip when CurrentTab == that index. On this modlist STAT hosts MAGAZINES/NEEDS/
      // DISEASE (PageNumberToInsert=0). Our fixed 3-tab strip + always-rendered content fought that overlay (white
      // stuck list + input lockup). Now: 4 pooled EXTRA slots (fixed baked geometry, names setText'd per render
      // from the live _TabNames that PBT mutates) make PBT tabs visible/clickable, and content hides on PBT tabs.
      private var _pbtHits:Array = [];
      private static const PBT_SLOTS:int = 4;
      private static const PBT_PITCH:Number = 118;
      private function buildSubtabs():void
      {
         this._subtabs.graphics.clear();
         var names:Array = ["STATUS", "SPECIAL", "PERKS"]; var x:Number = Theme.CX;
         this._subFields = []; this._subUL = []; this._pbtHits = [];
         for (var i:int = 0; i < names.length; i++)
         {
            var t:TextField = Theme.tf(14, Theme.PHOS_DIM, true);
            this._subtabs.addChild(t); t.name = "s" + i; t.x = x; t.y = 0; Theme.setText(t, String(names[i]));
            this._subFields.push(t);
            var hit:Sprite = new Sprite(); hit.graphics.beginFill(0, 0.004); hit.graphics.drawRect(x - 4, -2, t.width + 8, 22); hit.graphics.endFill();
            hit.name = "h" + i; hit.buttonMode = true; hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onSubtabClick);
            this._subtabs.addChild(hit);
            this._subUL.push({ x:(x - 4), w:(t.width + 8) });
            x += t.width + 22;
         }
         // PBT extra slots (indexes 3..3+PBT_SLOTS-1): FIXED baked geometry (autoSize none, width set ONCE on the
         // fresh empty field -- build-window-safe); render only ever setText/textColor/visible on them.
         for (var e:int = 0; e < PBT_SLOTS; e++)
         {
            var ex:Number = x + e * PBT_PITCH;
            var et:TextField = Theme.tf(14, Theme.PHOS_DIM, true); et.autoSize = "none"; et.width = PBT_PITCH - 10; et.height = 20;
            this._subtabs.addChild(et); et.name = "s" + (3 + e); et.x = ex; et.y = 0; et.visible = false;
            this._subFields.push(et);
            var eh:Sprite = new Sprite(); eh.graphics.beginFill(0, 0.004); eh.graphics.drawRect(ex - 4, -2, PBT_PITCH - 6, 22); eh.graphics.endFill();
            eh.name = "h" + (3 + e); eh.buttonMode = true; eh.visible = false; eh.addEventListener(MouseEvent.MOUSE_DOWN, this.onSubtabClick);
            this._subtabs.addChild(eh); this._pbtHits.push(eh);
            this._subUL.push({ x:(ex - 4), w:(PBT_PITCH - 6) });
         }
         this.updateSubtabs();
      }
      // UPDATE-ONLY: recolour frozen labels, fill the PBT extra slots from the live _TabNames (PBT pushes names
      // into it at runtime), toggle slot visibility, redraw the three-dot active indicator.
      private function updateSubtabs():void
      {
         this._subtabs.graphics.clear();
         for (var i:int = 0; i < this._subFields.length; i++)
         {
            var f:TextField = this._subFields[i] as TextField;
            if (i >= 3)
            {
               var nm:String = (_TabNames != null && i < _TabNames.length && _TabNames[i] != null) ? String(_TabNames[i]) : null;
               f.visible = (nm != null);
               if (i - 3 < this._pbtHits.length) { (this._pbtHits[i - 3] as Sprite).visible = (nm != null); }
               if (nm != null) { Theme.setText(f, nm); } else { continue; }
            }
            var on:Boolean = (i == this._curTab);
            f.textColor = on ? Theme.PHOS_BRIGHT : Theme.PHOS_DIM;
            if (on && i < this._subUL.length) {
               var cx:Number = this._subUL[i].x + this._subUL[i].w / 2; var dy:Number = 22; var dr:Number = 1.4; var gap:Number = 7;
               this._subtabs.graphics.beginFill(Theme.SEL, 0.95);
               this._subtabs.graphics.drawCircle(cx - gap, dy, dr); this._subtabs.graphics.drawCircle(cx, dy, dr); this._subtabs.graphics.drawCircle(cx + gap, dy, dr);
               this._subtabs.graphics.endFill();
            }
         }
      }
      private var _menu:Object = null;
      private function acquireMenu():Object
      {
         if (this._menu != null) { return this._menu; }
         try { if (stage != null && stage.numChildren > 0) { this._menu = stage.getChildAt(0)["Menu_mc"]; } } catch (er:*) { this._menu = null; }
         return this._menu;
      }
      private function onSubtabClick(e:MouseEvent):void
      {
         var i:int = int(e.currentTarget.name.substr(1));
         if (i == this._curTab) { return; }
         // PBT extra slots: only route if a PBT tab actually occupies that index right now.
         if (i >= 3 && (_TabNames == null || i >= _TabNames.length)) { return; }
         this.sfx("UIMenuPrevNext");
         var m:Object = this.acquireMenu();
         var routed:Boolean = false;
         if (m != null) { try { m.TryToSetTab(i); routed = true; } catch (er:*) { routed = false; } }
         if (!routed) { BGSExternalInterface.call(this.codeObj, "onNewTab", i); }
      }

      private var _lifeEvt:Boolean = false;
      override protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void
      {
         super.onPipboyChangeEvent(param1);
         if (!this._lifeEvt) { this._lifeEvt = true; Theme.life("ST.e" + param1.DataObj.CurrentTab); }   // first data event + tab at that moment
         this.ensureText(); if (!this._textBuilt) { return; }
         var d:Pipboy_DataObj = param1.DataObj; this._lastData = d; if (this._dbg != null) { this._dbg.change(); this._dbg.pageTab(d.CurrentPage, d.CurrentTab); }
         this._curTab = d.CurrentTab; this.updateSubtabs();
         // 0.0.50 PBT COMPAT: CurrentTab >= 3 = a PipboyTabs-injected tab (MAGAZINES/NEEDS/DISEASE here). PBT's
         // own clip overlays the page for it, so hide ALL our content (subtab strip stays) and render nothing --
         // previously our content kept rendering underneath and fought PBT's list (overlap + input lockup).
         var pbtOn:Boolean = (this._curTab >= 3);
         var statusOn:Boolean = (this._curTab == 0);
         this._status.visible = statusOn && !pbtOn;
         this._list.visible = !statusOn && !pbtOn; this._listPanel.visible = !statusOn && !pbtOn; this._descPanel.visible = !statusOn && !pbtOn;
         this._levelBox.visible = !pbtOn;
         if (pbtOn)
         {
            Theme.setText(this._title, (_TabNames != null && this._curTab < _TabNames.length) ? String(_TabNames[this._curTab]) : "EXTENSION");
            SetIsDirty();
            return;
         }
         Theme.setText(this._title, (this._curTab == 1) ? "S.P.E.C.I.A.L" : (this._curTab == 2 ? "PERKS" : "STATUS"));
         this._stim.ButtonText = "STIMPAK (" + d.StimpakCount + ")";
         this._rad.ButtonText = "RADAWAY (" + d.RadawayCount + ")";
         this._vbtn.ButtonText = this._showVaultBoy ? "CHARACTER" : "VAULT BOY";
         this.renderLevel(d);   // LEVEL bar on all vanilla tabs
         if (statusOn) { this.renderStatus(d); }
         else if (this._curTab == 1) { this.listHeaders("S.P.E.C.I.A.L.", "ATTRIBUTE", "VALUE"); this._list.setItems(d.SPECIALList, this.specialAdapter); this.onListSel(this._list.selectedIndex); }
         else { this.listHeaders("PERKS", "PERK / EFFECT", "RANK"); this._list.setItems(d.PerksList, this.perkAdapter); this.onListSel(this._list.selectedIndex); }
         SetIsDirty();
      }

      // UPDATE-ONLY: swap the list panel h3 + column-header text per sub-tab.
      private function listHeaders(h3:String, colL:String, colR:String):void
      {
         if (this._listH3 == null) { return; }
         Theme.setText(this._listH3, h3); Theme.setText(this._listColL, colL); Theme.setText(this._listColR, colR);
      }

      // UPDATE-ONLY: LEVEL number + XP bar (graphics). Runs on every tab.
      private function renderLevel(d:Pipboy_DataObj):void
      {
         if (this._lvNum == null) { return; }
         var boxX:Number = Theme.CR - 184; this._levelBox.x = boxX; this._levelBox.y = Theme.SUB_Y;
         Theme.setText(this._lvNum, String(d.XPLevel));
         var g:* = this._levelBox.graphics; g.clear();
         var bx:Number = 66, bw:Number = 184 - 66, by:Number = 4;
         g.lineStyle(1, Theme.PHOS, 0.5); g.moveTo(bx, by); g.drawRoundRect(bx, by, bw, 9, 3, 3); g.lineStyle();
         g.beginFill(0x000000, 0.4); g.drawRoundRect(bx + 1, by + 1, bw - 2, 7, 2, 2); g.endFill();
         g.beginFill(Theme.PHOS, 0.9); g.drawRoundRect(bx + 1, by + 1, (bw - 2) * Math.max(0, Math.min(1, d.XPProgressPct)), 7, 2, 2); g.endFill();
      }

      // UPDATE-ONLY STATUS render: meters/tiles/limbs/effects text + all Shape graphics (no field ops).
      private function renderStatus(d:Pipboy_DataObj):void
      {
         var P:Number = Theme.PAD;
         // ----- meters -----
         var mg:* = this._meters.graphics; mg.clear();
         var mCur:Array = [d.CurrHP, d.CurrAP, 0];
         var mMax:Array = [d.MaxHP, d.MaxAP, 0];
         var mCol:Array = [Theme.PHOS, Theme.SEL, Theme.CRIT];
         var mStr:Array = [Math.round(d.CurrHP) + " / " + Math.round(d.MaxHP), Math.round(d.CurrAP) + " / " + Math.round(d.MaxAP), "0"];
         for (var mi:int = 0; mi < 3; mi++) {
            var my0:Number = Theme.BY + mi * METER_PITCH;
            mg.beginFill(Theme.PANEL, 0.5); mg.drawRoundRect(Theme.CX, my0, LEFTW, METER_H, 6, 6); mg.endFill();
            mg.lineStyle(1, Theme.LINE, 0.3); mg.moveTo(Theme.CX + 0.5, my0 + 0.5); mg.drawRoundRect(Theme.CX + 0.5, my0 + 0.5, LEFTW - 1, METER_H - 1, 6, 6); mg.lineStyle();   // 0.0.57: moveTo parks the pen (GFx draws a stray segment from the stale pen position into stroked rects -- the diagonal-line artifact)
            Theme.setText(this._mVal[mi], String(mStr[mi]));
            var barY:Number = my0 + 28, bx:Number = Theme.CX + 12, bw:Number = LEFTW - 24;
            var frac:Number = (Number(mMax[mi]) > 0) ? (Number(mCur[mi]) / Number(mMax[mi])) : 0; if (frac < 0) frac = 0; if (frac > 1) frac = 1;
            mg.lineStyle(1, uint(mCol[mi]), 0.5); mg.moveTo(bx, barY); mg.drawRoundRect(bx, barY, bw, 8, 2, 2); mg.lineStyle();
            mg.beginFill(0x000000, 0.4); mg.drawRoundRect(bx + 1, barY + 1, bw - 2, 6, 2, 2); mg.endFill();
            mg.beginFill(uint(mCol[mi]), 0.9); mg.drawRoundRect(bx + 1, barY + 1, (bw - 2) * frac, 6, 2, 2); mg.endFill();
         }
         // ----- SPECIAL tiles -----
         var sg:* = this._special.graphics; sg.clear();
         var sp:Array = d.SPECIALList;
         var tileY:Number = Theme.BY + 3 * METER_PITCH + 14;
         var tileX0:Number = Theme.CX + (LEFTW - (7 * TILE_W + 6 * TILE_GAP)) / 2;
         for (var s:int = 0; s < 7; s++) {
            var tx:Number = tileX0 + s * (TILE_W + TILE_GAP);
            sg.beginFill(Theme.PANEL, 0.5); sg.drawRoundRect(tx, tileY, TILE_W, TILE_H, 5, 5); sg.endFill();
            sg.lineStyle(1, Theme.LINE, 0.4); sg.moveTo(tx + 0.5, tileY + 0.5); sg.drawRoundRect(tx + 0.5, tileY + 0.5, TILE_W - 1, TILE_H - 1, 5, 5); sg.lineStyle();
            var val:String = (sp != null && s < sp.length && sp[s] != null && sp[s].value != null) ? String(sp[s].value) : "-";
            Theme.setText(this._spVal[s], val);
         }
         // ----- figure + limbs -----
         if (this._vb != null) { if (this._showVaultBoy) { this._vb.visible = true; try { this._vb.setFlags(d.BodyFlags, d.HeadFlags); } catch (ev:Error) {} } else { this._vb.visible = false; } }
         var lg:* = this._limbs.graphics; lg.clear();
         var conds:Array = [d.HeadCondition, d.LArmCondition, d.RArmCondition, d.TorsoCondition, d.LLegCondition, d.RLegCondition];
         for (var i:int = 0; i < LIMBS.length; i++) {
            var L:Array = LIMBS[i];
            var cx:Number = Number(L[1]), cy:Number = Number(L[2]), tx2:Number = Number(L[3]), ty2:Number = Number(L[4]);
            var cond:Number = Number(conds[int(L[5])]);
            var sev:uint = (cond < 0.35) ? Theme.CRIT : (cond < 0.70 ? Theme.WARN : Theme.PHOS);
            // leader from the chip edge nearest the target to the target dot
            var startY:Number = (ty2 > cy) ? (cy + CHIPH / 2) : (cy - CHIPH / 2);
            lg.lineStyle(1, Theme.PHOS_DIM, 0.5); lg.moveTo(cx, startY); lg.lineTo(tx2, ty2); lg.lineStyle();
            lg.beginFill(Theme.PHOS_DIM, 0.9); lg.drawCircle(tx2, ty2, 2); lg.endFill();
            // chip
            lg.beginFill(Theme.PANEL, 0.9); lg.drawRoundRect(cx - CHIPW / 2, cy - CHIPH / 2, CHIPW, CHIPH, 5, 5); lg.endFill();
            lg.lineStyle(1, sev, 0.75); lg.moveTo(cx - CHIPW / 2, cy - CHIPH / 2); lg.drawRoundRect(cx - CHIPW / 2, cy - CHIPH / 2, CHIPW, CHIPH, 5, 5); lg.lineStyle();
            (this._limbName[i] as TextField).textColor = sev;
            // condition bar under the name
            var lbx:Number = cx - CHIPW / 2 + 7, lbw:Number = CHIPW - 14, lby:Number = cy + CHIPH / 2 - 8;
            lg.lineStyle(1, sev, 0.4); lg.moveTo(lbx, lby); lg.drawRoundRect(lbx, lby, lbw, 4, 1, 1); lg.lineStyle();
            var lc:Number = Math.max(0, Math.min(1, cond));
            lg.beginFill(sev, 0.9); lg.drawRoundRect(lbx + 1, lby + 1, (lbw - 2) * lc, 2, 1, 1); lg.endFill();
         }
         // ----- ACTIVE EFFECTS -----
         var fx:Array = d.ActiveEffects;
         var count:int = (fx != null) ? fx.length : 0; if (count > EF_ROWS) { count = EF_ROWS; }
         var panelH:Number = P + 46 + (count < 1 ? 1 : count) * 22 + 4;
         var efW:Number = (Theme.CR - EFX);
         var eg:* = this._effects.graphics; eg.clear();
         eg.beginFill(Theme.PANEL, 0.82); eg.drawRoundRect(0, 0, efW, panelH, 8, 8); eg.endFill();
         eg.lineStyle(1, Theme.LINE, 0.38); eg.moveTo(0.5, 0.5); eg.drawRoundRect(0.5, 0.5, efW - 1, panelH - 1, 8, 8); eg.lineStyle();
         eg.lineStyle(1, Theme.LINE, 0.2); eg.moveTo(P, P + 40); eg.lineTo(efW - P, P + 40); eg.lineStyle();
         for (var f:int = 0; f < EF_ROWS; f++) {
            var show:Boolean = (f < count && fx[f] != null);
            (this._efRowL[f] as TextField).visible = show;
            if (show) { Theme.setText(this._efRowL[f] as TextField, (fx[f].text != null) ? String(fx[f].text) : ""); }
            var hasSrc:Boolean = (show && fx[f].source != null);
            (this._efRowR[f] as TextField).visible = hasSrc;
            if (hasSrc) { Theme.setText(this._efRowR[f] as TextField, String(fx[f].source)); }
         }
      }

      public function debugRects():Array { return this._panels; }

      private function specialAdapter(e:Object):Object { return { label:(e != null && e.text != null ? String(e.text) : ""), right:(e != null && e.value != null ? String(e.value) : ""), star:false, legendary:false, dim:false }; }
      private function perkAdapter(e:Object):Object { return { label:(e != null && e.text != null ? String(e.text) : ""), right:(e != null && e.rank != null ? String(e.rank) : ""), star:false, legendary:false, dim:false }; }

      // UPDATE-ONLY: fill the description panel for the selected attribute/perk.
      private function onListSel(i:int):void
      {
         if (this._descH3 == null) { return; }
         var arr:Array = (this._curTab == 1) ? (this._lastData ? this._lastData.SPECIALList : null) : (this._lastData ? this._lastData.PerksList : null);
         var e:Object = (arr != null && i >= 0 && i < arr.length) ? arr[i] : null;
         var nm:String = (e != null && e.text != null) ? String(e.text).toUpperCase() : "";
         Theme.setText(this._descH3, nm);
         Theme.setText(this._descBody, (e != null && e.description != null) ? String(e.description) : "");
      }

      private function doStim():void { this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "UseStimpak"); }
      private function doRad():void  { this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "UseRadaway"); }
      private function doToggleFigure():void { this._showVaultBoy = !this._showVaultBoy; this._vbtn.ButtonText = this._showVaultBoy ? "CHARACTER" : "VAULT BOY"; this.sfx("UIMenuPrevNext"); if (this._lastData != null && this._curTab == 0) { this.renderStatus(this._lastData); } }
      private function onLimbClick(e:MouseEvent):void { this.doStim(); }

      private function onPageStage(e:Event):void { Theme.life("ST.s"); this.ensureText(); if (this._vb != null) { this._vb.begin(); } if (stage != null) { stage.addEventListener(KeyboardEvent.KEY_DOWN, this.onKey); } }
      private function onPageUnstage(e:Event):void { if (stage != null) { stage.removeEventListener(KeyboardEvent.KEY_DOWN, this.onKey); } }

      private function onKey(e:KeyboardEvent):void {
         if (this._dbg != null) {
            this._dbg.input("key", e.keyCode, e.target);
            if (this._dbg.isDumpKey(e.keyCode)) {
               this._dbg.clearDump(); this._dbg.toggleDump();
               if (this._lastData != null) {
                  this._dbg.dump("SPECIALList[0]", (this._lastData.SPECIALList != null && this._lastData.SPECIALList.length > 0) ? this._lastData.SPECIALList[0] : null);
                  this._dbg.dump("ActiveEffects[0]", (this._lastData.ActiveEffects != null && this._lastData.ActiveEffects.length > 0) ? this._lastData.ActiveEffects[0] : null);
                  this._dbg.dump("PerksList[0]", (this._lastData.PerksList != null && this._lastData.PerksList.length > 0) ? this._lastData.PerksList[0] : null);
               }
               return;
            }
         }
         if (this._curTab != 0) { this._list.handleKey(e.keyCode); }
      }

      override public function ProcessUserEvent(param1:String, param2:Boolean):Boolean
      {
         if (!param2)
         {
            switch (param1)
            {
               case "Accept":    this.doStim();         return true;
               case "XButton":   this.doRad();          return true;
               case "LShoulder": this.doToggleFigure(); return true;
            }
         }
         return false;
      }
   }
}
