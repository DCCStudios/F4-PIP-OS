package
{
   import Shared.AS3.BSButtonHintData;
   import Shared.BGSExternalInterface;
   import pipos.PipList;
   import pipos.Theme;
   import pipos.Debug;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.text.TextField;

   // PIP-OS Data page: Quests / Workshops / Stats. Keeps vanilla plumbing (onQuestSelection,
   // SetQuestActive, ShowQuestOnMap, ShowWorkshopOnMap, PlaySmallTransition).
   public class PipOS_DataPage extends PipboyPage
   {
      private var _title:TextField;
      private var _questTitle:TextField;    // parity: left-panel "QUEST LOG"/"WORKSHOPS"/"STATS" header (mockup .panel h3)
      private var _colHead:Sprite;          // "QUEST ... STATUS" dim column-header row (mockup .rows .head); quests-tab only
      private var _subtabs:Sprite;
      private var _list:PipList;
      private var _detail:Sprite;
      private var _curTab:int = -1;
      private var _showSummary:Boolean = false;
      private var _lastData:Pipboy_DataObj;
      private var _displayMap:Array = [];   // list-row index -> original data index (-1 for separator)
      private var _dbg:Debug;
      private var _objArray:Array = [];
      private var _selQuest:Object = null;
      private var _detailHead:TextField; private var _objRows:Array = []; private var _detailSummary:TextField;
      private var _subFields:Array = [];    // pooled sub-tab label fields (built once in buildText)
      private var _subUL:Array = [];        // frozen underline rects {x,w} per sub-tab (no width read on update path)
      private const OBJ_POOL:int = 14;
      private const OBJ_SLOT:Number = 44;   // P0 (0.0.26): fixed 2-line objective slot (fixed .y set once at creation)
      private const OBJ_Y0:Number = 40;     // first objective row top (below _detailHead)
      private var _panels:Array = [];       // panel rects for the DEBUG clearance overlay

      private var _map:BSButtonHintData;
      private var _sum:BSButtonHintData;

      public function PipOS_DataPage()
      {
         super();
         _TabNames = new Array("$QUESTS","$SANCTUARY","$LOG");
         this.buildPanels();
         this._dbg = new Debug("DATA"); addChild(this._dbg);
         Theme.life("DA.c");   // 0.0.52 forensics
      }

      override protected function PopulateButtonHintData():*
      {
         this._map   = new BSButtonHintData("SHOW ON MAP","R","PSN_X","Xenon_X",1,this.doMap);
         this._sum   = new BSButtonHintData("SUMMARY","C","PSN_L1","Xenon_L1",1,this.doSummary);
         // Parity: the misleading "TRACK" keybar chip is removed (mockup DATA keybar has none; the chip was dead
         // on Workshops/Stats). The TRACK ACTION stays reachable via ProcessUserEvent "Accept" (Enter / Xenon_A)
         // and a row click (onListPress -> doTrack) -- only the chip is gone, not the capability.
         _buttonHintDataV.push(this._map); _buttonHintDataV.push(this._sum);
      }

      override protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.Quest; }
      private function sfx(ev:String):void { BGSExternalInterface.call(this.codeObj, "PlaySound", ev); }

      private function buildPanels():void
      {
         var P:Number = Theme.PAD;
         // 16:9 grid (mockup DATA: 1fr(880) | 430, gap16). List left, detail right.
         var listW:Number = Theme.ms(880);       // 704   quest/list column width
         var detailX:Number = Theme.mx(1136);    // 708.8 detail column left
         var detailW:Number = Theme.ms(430);     // 344   detail column width
         this._subtabs = new Sprite(); this._subtabs.y = Theme.SUB_Y; addChild(this._subtabs);
         var g:* = this.graphics;
         Theme.panelR(g, this._panels, Theme.CX, Theme.BY, listW, Theme.BB - Theme.BY);
         Theme.panelR(g, this._panels, detailX, Theme.BY, detailW, Theme.BB - Theme.BY);
         this._list = new PipList(listW - 2 * P, 26, 19);   // 19 rows: a header band (QUEST LOG, mockup h3) is reserved above
         this._list.x = Theme.CX + P; this._list.y = Theme.BY + 48; this._list.onSelectionChange = this.onListSel; this._list.onItemPress = this.onListPress; this._list.playSound = this.sfx; addChild(this._list);
         this._detail = new Sprite(); this._detail.x = detailX + P; this._detail.y = Theme.BY + P; addChild(this._detail);
         this._detail.scrollRect = new Rectangle(0, 0, detailW - 2 * P, (Theme.BB - Theme.BY) - 2 * P);
         addEventListener(Event.ADDED_TO_STAGE, this.onPageStage);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onPageUnstage);
      }

      private function buildText():void
      {
         // No standalone page title (mockup: the sidebar shows the active page). Keep the pooled field, hidden.
         this._title = Theme.mk(this, 22, Theme.PHOS_BRIGHT, true); this._title.visible = false; Theme.setText(this._title, "QUESTS");
         // Parity: left-panel header over the list (mockup .panel h3 "Quest Log"). POOLED here (geometry-before-text);
         // its text is switched per sub-tab (QUEST LOG / WORKSHOPS / STATS) via setText on the update path only.
         this._questTitle = Theme.mk(this, 12, Theme.PHOS_BRIGHT, true); this._questTitle.x = Theme.CX + Theme.PAD; this._questTitle.y = Theme.BY + 8;   // 0.0.46: bright panel heading (mockup)
         var qhf:* = this._questTitle.defaultTextFormat; qhf.letterSpacing = 1.4; this._questTitle.defaultTextFormat = qhf; Theme.setText(this._questTitle, "QUEST LOG");
         // "QUEST ... STATUS" dim column header (mockup .rows .head), aligned over the list's NAME/right columns.
         // Quests-tab only (toggled in onPipboyChangeEvent). Structural label -> keeps the wider header letterSpacing.
         var lhx:Number = Theme.CX + Theme.PAD;                 // list left in page coords
         var lInnerW:Number = Theme.ms(880) - 2 * Theme.PAD;    // list inner width (== PipList _w)
         this._colHead = new Sprite(); addChild(this._colHead);
         var chL:TextField = Theme.mk(this._colHead, 10, Theme.PHOS_DIM, true); chL.x = lhx + 12; chL.y = Theme.BY + 30; var chlf:* = chL.defaultTextFormat; chlf.letterSpacing = 1; chL.defaultTextFormat = chlf; Theme.setText(chL, "QUEST");
         var chR:TextField = Theme.mk(this._colHead, 10, Theme.PHOS_DIM, true, "right"); chR.autoSize = "none"; chR.width = 96; chR.height = 14; chR.x = lhx + lInnerW - 12 - 96; chR.y = Theme.BY + 30; var chrf:* = chR.defaultTextFormat; chrf.letterSpacing = 1; chR.defaultTextFormat = chrf; Theme.setText(chR, "STATUS");
         this._colHead.graphics.lineStyle(1, Theme.LINE, 0.3); this._colHead.graphics.moveTo(lhx + 2, Theme.BY + 45); this._colHead.graphics.lineTo(lhx + lInnerW - 2, Theme.BY + 45); this._colHead.graphics.lineStyle();
         // P1: create the FULL detail/objective field set ONCE, on-stage. Render only updates .text/.visible
         // on these pre-attached, font-resolved fields - NEVER `new TextField` in a handler (FindFont AV).
         var innerW:Number = Theme.ms(430) - 2 * Theme.PAD;
         this._detailHead = Theme.mk(this._detail, 18, Theme.PHOS_BRIGHT, true); this._detailHead.autoSize = "none"; this._detailHead.width = innerW; this._detailHead.height = 24; this._detailHead.x = 0; this._detailHead.y = 0;
         this._objRows = [];
         // P0 (0.0.26, crash-2026-08-17: renderDetail SetY -> FindFont on the quest-click render path): each
         // objective row uses a FIXED generous 2-line slot; its .y is set ONCE HERE on the fresh empty field
         // (geometry-before-text). renderDetail then updates ONLY .text/.visible/.textColor and NEVER re-sets
         // .y on a pooled text-bearing field (that reformat is the SetY -> DocView::Format -> FindFont(NULL)
         // crash frame). Multiline+wordWrap set once at creation. Fixed spacing (looser than dynamic measure)
         // is the deliberate trade: crash-safety over pixel-tight spacing.
         for (var oi:int = 0; oi < OBJ_POOL; oi++) {
            var r:TextField = Theme.mk(this._detail, 15, Theme.PHOS, false); r.autoSize = "none"; r.multiline = true; r.wordWrap = true; r.width = innerW; r.height = OBJ_SLOT; r.x = 0; r.y = OBJ_Y0 + oi * OBJ_SLOT; r.visible = false; this._objRows.push(r);
         }
         // Summary sits at a FIXED y below the common objective range (~7 slots). Fixed => renderDetail never
         // sets its geometry after text (same SetY crash class). Quests with many objectives AND the summary
         // toggled may visually overlap the lower objectives (rare, cosmetic; crash-safe).
         this._detailSummary = Theme.mk(this._detail, 13, Theme.PHOS_DIM, false); this._detailSummary.autoSize = "none"; this._detailSummary.multiline = true; this._detailSummary.wordWrap = true; this._detailSummary.width = innerW; this._detailSummary.height = 220; this._detailSummary.x = 0; this._detailSummary.y = OBJ_Y0 + 7 * OBJ_SLOT; this._detailSummary.visible = false;
         this.buildSubtabs();   // pool the sub-tab strip ONCE, on-stage (data changes fire reentrantly inside quest clicks -> never rebuild it there)
         // Lazy-build cleanup (mirrors InvPage A2): force the PipList pool build NOW, inside this proven-safe on-stage
         // build window, so a first render() can never fire from an interaction path (onWheel/handleKey) later.
         if (this._list != null && stage != null) { this._list.render(); }
         // Per-page bottom keybar: only DATA's wired actions (SHOW ON MAP / SUMMARY) + ESC BACK. TRACK stays on
         // Enter/Accept (intentionally no chip -- it is dead on the Workshops/Stats sub-tabs).
         // 0.0.57: keybar restored (see InvPage note).
         Theme.keybar(this, [{key:"ESC",label:"BACK"},{key:"R",label:"SHOW ON MAP"},{key:"C",label:"SUMMARY"},{key:"T",label:"PERK CHART"}], Theme.my(858));
      }

      private var _textBuilt:Boolean = false;
      private function ensureText():void { if (this._textBuilt || stage == null) { return; } this._textBuilt = true; this.buildText(); }

      // POOL BUILDER (called ONCE from buildText, on-stage). Labels are constants; all fields are BOLD so their
      // width is FROZEN independent of active state (active is shown by colour + underline, not weight). Measure
      // t.width ONCE here (build-time read) to place the hit rects + advance x, then freeze the underline rects.
      // 0.0.50 PIPBOYTABS COMPAT (see PipOS_StatsPage.buildSubtabs for the full mechanism note): PBT pushes extra
      // tab names onto this page's _TabNames at runtime and overlays its own clip when that tab is current. DATA
      // hosts AFFINITY + CHALLENGES on this modlist (PageNumberToInsert=2). Pooled fixed-slot extras render them.
      private var _pbtHits:Array = [];
      private static const PBT_SLOTS:int = 4;
      private static const PBT_PITCH:Number = 118;
      private function buildSubtabs():void
      {
         this._subtabs.graphics.clear();
         var names:Array = ["QUESTS","WORKSHOPS","STATS"]; var x:Number = Theme.CX;
         this._subFields = []; this._subUL = []; this._pbtHits = [];
         for (var i:int = 0; i < names.length; i++)
         {
            var t:TextField = Theme.tf(14, Theme.PHOS_DIM, true);
            this._subtabs.addChild(t); t.name = "s" + i; t.x = x; t.y = 0; Theme.setText(t, names[i]);
            this._subFields.push(t);
            var hit:Sprite = new Sprite(); hit.graphics.beginFill(0,0.004); hit.graphics.drawRect(x-4,-2,t.width+8,22); hit.graphics.endFill();
            hit.name = "h"+i; hit.buttonMode = true; hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onSubtabClick);
            this._subtabs.addChild(hit);
            this._subUL.push({ x:(x-4), w:(t.width+8) });
            x += t.width + 26;
         }
         // PBT extra slots (fixed baked geometry set ONCE on fresh empty fields; render = setText/visible only).
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
      // UPDATE-ONLY (tab change): recolour the frozen labels, fill PBT extra slots from the live _TabNames, and
      // redraw the three-dot active indicator. No field creation, no geometry write, no width read.
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
            // Parity: active sub-tab marked by the mockup's three-dot ". . ." indicator (font-independent vector dots
            // on this pooled layer), matching INV -- was a solid underline bar. Graphics-only redraw.
            if (on && i < this._subUL.length) {
               var cx:Number = this._subUL[i].x + this._subUL[i].w / 2; var dy:Number = 22; var dr:Number = 1.4; var gap:Number = 7;
               this._subtabs.graphics.beginFill(Theme.SEL, 0.95);
               this._subtabs.graphics.drawCircle(cx - gap, dy, dr); this._subtabs.graphics.drawCircle(cx, dy, dr); this._subtabs.graphics.drawCircle(cx + gap, dy, dr);
               this._subtabs.graphics.endFill();
            }
         }
      }
      // P1-A: route sub-tab clicks through the shell's guarded TryToSetTab(uint), Chrome-idiom acquire.
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
         if (this._dbg != null) this._dbg.input("subtab", i, e.currentTarget);
         if (i == this._curTab) { return; }
         // PBT extra slots: only route if a PBT tab actually occupies that index right now.
         if (i >= 3 && (_TabNames == null || i >= _TabNames.length)) { return; }
         this.sfx("UIMenuPrevNext");
         BGSExternalInterface.call(this.codeObj,"PlaySmallTransition");
         var m:Object = this.acquireMenu();
         var routed:Boolean = false;
         if (m != null) { try { m.TryToSetTab(i); routed = true; } catch (er:*) { routed = false; } }
         if (!routed) { BGSExternalInterface.call(this.codeObj,"onNewTab",i); }
      }

      override protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void
      {
         super.onPipboyChangeEvent(param1);
         this.ensureText(); if (!this._textBuilt) { return; }
         var d:Pipboy_DataObj = param1.DataObj; this._lastData = d; if (this._dbg != null) { this._dbg.change(); this._dbg.pageTab(d.CurrentPage, d.CurrentTab); } this._curTab = d.CurrentTab; this.updateSubtabs();
         // 0.0.50 PBT COMPAT: CurrentTab >= 3 = a PipboyTabs-injected tab (AFFINITY/CHALLENGES here); its clip
         // overlays the page, so hide ALL our content (subtab strip stays) and render nothing.
         var pbtOn:Boolean = (this._curTab >= 3);
         this._list.visible = !pbtOn; this._detail.visible = !pbtOn;
         if (this._questTitle != null) { this._questTitle.visible = !pbtOn; }
         if (pbtOn)
         {
            if (this._colHead != null) { this._colHead.visible = false; }
            Theme.setText(this._title, (_TabNames != null && this._curTab < _TabNames.length) ? String(_TabNames[this._curTab]) : "EXTENSION");
            SetIsDirty();
            return;
         }
         Theme.setText(this._title, (this._curTab == 1) ? "WORKSHOPS" : (this._curTab == 2 ? "STATS" : "QUESTS"));
         if (this._questTitle != null) { Theme.setText(this._questTitle, (this._curTab == 1) ? "WORKSHOPS" : (this._curTab == 2 ? "STATS" : "QUEST LOG")); }
         if (this._colHead != null) { this._colHead.visible = (this._curTab == 0); }   // QUEST/STATUS header shows on the quests tab only
         if (this._curTab == 0) { this.buildQuestDisplay(d.QuestsList); }
         else if (this._curTab == 1) { this.identityMap(d.WorkshopsList); this._list.setItems(d.WorkshopsList, this.workshopAdapter); }
         else { this.buildStatsDisplay(d.GeneralStatsList); }
         SetIsDirty();
      }

      private function identityMap(arr:Array):void
      {
         this._displayMap = [];
         var n:int = arr != null ? arr.length : 0; if (n > 600) { n = 600; }   // hard cap
         for (var i:int = 0; i < n; i++) { this._displayMap.push(i); }
      }

      // Reorder quests: active first, a COMPLETED separator, then dimmed completed quests. The list
      // rows no longer map 1:1 to QuestsList indices, so _displayMap translates back for the engine calls.
      private function buildQuestDisplay(qs:Array):void
      {
         var display:Array = []; this._displayMap = [];
         var active:Array = [], completed:Array = [];
         var n:int = qs != null ? qs.length : 0; if (n > 600) { n = 600; }   // hard cap
         for (var i:int = 0; i < n; i++) { if (qs[i] != null && qs[i].isCompleted == true) { completed.push(i); } else { active.push(i); } }
         for each (var ai:int in active) { display.push({ q: ai, e: qs[ai] }); this._displayMap.push(ai); }
         if (completed.length > 0)
         {
            display.push({ separator: true }); this._displayMap.push(-1);
            for each (var ci:int in completed) { display.push({ q: ci, e: qs[ci] }); this._displayMap.push(ci); }
         }
         this._list.setItems(display, this.questAdapter);
      }

      private function questAdapter(e:Object):Object
      {
         if (e != null && e.separator == true) { return { separator:true, label:"COMPLETED" }; }
         var q:Object = (e != null) ? e.e : null;
         var done:Boolean = (q != null && q.isCompleted == true);
         // Every quest shows a STATUS under the column header: DONE (completed), TRACKED (player-tracked),
         // else ACTIVE. Answers the 0.0.40 "none of the quests have statuses" note; the column is never blank.
         var status:String = done ? "DONE" : ((q != null && q.isTracked == true) ? "TRACKED" : "ACTIVE");
         return { label: (q != null && q.text != null ? String(q.text) : ""), right: status, star:false, legendary:false, dim: done };
      }
      private function workshopAdapter(e:Object):Object { return { label:(e!=null&&e.text!=null?String(e.text):""), right:(e!=null&&e.value!=null?String(e.value):""), star:false, legendary:false, dim:false }; }
      // P2-E: vanilla StatsTab feeds GeneralStatsList to a CATEGORY list, then each category's .statArray to
      // a VALUE list (Stats_ValuesListEntry: base text = entry.text, Value_tf = entry.value). Our single list
      // was rendering the categories only, so the actual stat text/values never showed. Flatten it: a category
      // header (separator) followed by its statArray rows (label = .text, right = .value). If a category is
      // itself a flat stat (no statArray) fall back to rendering it as one label/value row. Pre-shaped entries
      // are passed straight through selfAdapter (no re-mapping; stats are informational, not selectable).
      private function statLabel(o:Object):String { if (o == null) { return ""; } if (o.text != null) { return String(o.text); } if (o.name != null) { return String(o.name); } return ""; }
      private function selfAdapter(e:Object):Object { return e; }
      private function buildStatsDisplay(gs:Array):void
      {
         var display:Array = []; this._displayMap = [];
         var n:int = gs != null ? gs.length : 0; if (n > 200) { n = 200; }
         for (var i:int = 0; i < n; i++)
         {
            var cat:Object = gs[i]; if (cat == null) { continue; }
            var sa:Array = (cat.statArray is Array) ? (cat.statArray as Array) : null;
            if (sa != null && sa.length > 0)
            {
               display.push({ separator:true, label: this.statLabel(cat) }); this._displayMap.push(-1);
               var m:int = sa.length; if (m > 400) { m = 400; }
               for (var j:int = 0; j < m; j++)
               {
                  var st:Object = sa[j]; if (st == null) { continue; }
                  display.push({ label:(st.text != null ? String(st.text) : ""), right:(st.value != null ? String(st.value) : ""), star:false, legendary:false, dim:false }); this._displayMap.push(-1);
               }
            }
            else
            {
               display.push({ label: this.statLabel(cat), right:(cat.value != null ? String(cat.value) : ""), star:false, legendary:false, dim:false }); this._displayMap.push(-1);
            }
         }
         this._list.setItems(display, this.selfAdapter);
      }

      private function mapIndex(listIndex:int):int
      {
         return (listIndex >= 0 && listIndex < this._displayMap.length) ? int(this._displayMap[listIndex]) : -1;
      }

      private function questAt(listIndex:int):Object
      {
         var orig:int = this.mapIndex(listIndex);
         if (orig < 0 || this._lastData == null || this._lastData.QuestsList == null || orig >= this._lastData.QuestsList.length) { return null; }
         return this._lastData.QuestsList[orig];
      }

      private function onListSel(i:int):void
      {
         if (this._curTab == 0) {
            // C3/G5: vanilla passes (engine-filled objectives array, the QUEST OBJECT, this).
            // Passing an index made the native side read .formID off an int -> AV. Guard null.
            this._selQuest = this.questAt(i);
            if (this._selQuest != null) {
               this._objArray = [];
               BGSExternalInterface.call(this.codeObj, "onQuestSelection", this._objArray, this._selQuest, this);
            }
         }
         this.renderDetail(i);
      }
      public function onObjectivesReady():* { this.renderDetail(this._list.selectedIndex); SetIsDirty(); }
      private function onListPress(i:int):void { this.doTrack(); }

      private function renderDetail(i:int):void
      {
         if (this._detailHead == null) { return; }   // text not built yet (off-stage)
         var e:Object = (this._curTab == 0) ? this.questAt(i) : null;
         // Parity: detail header matches the mockup #objtitle "Objectives . <name>" (static "OBJECTIVES" when no
         // quest is selected). Update-only setText -- keeps the quest name (an improvement) under the mockup label.
         Theme.setText(this._detailHead, (e != null && e.text != null) ? ("OBJECTIVES · " + String(e.text)) : "OBJECTIVES");
         // P0 (0.0.26): render path is UPDATE-ONLY (.text/.visible/.textColor). Row/summary .y are FIXED at
         // creation (buildText) -> NO geometry is set on any pooled text-bearing field here, so the SetY ->
         // FindFont(NULL) crash on the quest-click path cannot occur.
         var shown:int = 0;
         if (this._objArray != null) {
            for (var o:int = 0; o < this._objArray.length && shown < this._objRows.length; o++) {
               var ob:Object = this._objArray[o]; if (ob == null) { continue; }
               var met:Boolean = (ob.isCompleted == true || ob.completed == true);
               var row:TextField = this._objRows[shown];
               row.visible = true;
               Theme.setText(row, (met ? "[x] " : "[ ] ") + (ob.text != null ? String(ob.text) : ""));
               row.textColor = met ? Theme.PHOS_DIM : Theme.PHOS;
               shown++;
            }
         }
         for (var k:int = shown; k < this._objRows.length; k++) { this._objRows[k].visible = false; }
         if (this._showSummary && e != null && e.description != null) {
            this._detailSummary.visible = true; Theme.setText(this._detailSummary, String(e.description));
         } else { this._detailSummary.visible = false; }
      }
      public function debugRects():Array { return this._panels; }

      private function doMap():void {
         if (this._curTab == 0) { var q:Object = this.questAt(this._list.selectedIndex); if (q == null) { return; } this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "ShowQuestOnMap", q.formID); }
         else if (this._curTab == 1) { var wo:int = this.mapIndex(this._list.selectedIndex); if (wo < 0 || this._lastData == null || this._lastData.WorkshopsList == null || wo >= this._lastData.WorkshopsList.length) { return; } var w:Object = this._lastData.WorkshopsList[wo]; if (w == null) { return; } this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "ShowWorkshopOnMap", w.mapMarkerID); }
      }
      private function doSummary():void { this._showSummary = !this._showSummary; this.sfx("UIMenuPrevNext"); this.renderDetail(this._list.selectedIndex); }
      private function doTrack():void { if (this._curTab != 0) { return; } var q:Object = this.questAt(this._list.selectedIndex); if (q == null) { return; } this.sfx((q.active == true) ? "UIMenuCancel" : "UIMenuOK"); BGSExternalInterface.call(this.codeObj, "SetQuestActive", q); }

      // Raw KEY_DOWN drives ONLY the list (up/down/enter). Keybar actions go through ProcessUserEvent
      // named controls (single path). Enter on a row (list press) tracks the quest.
      private function onPageStage(e:Event):void { this.ensureText(); if (stage != null) { stage.addEventListener(KeyboardEvent.KEY_DOWN, this.onKey); } }
      private function onPageUnstage(e:Event):void { if (stage != null) { stage.removeEventListener(KeyboardEvent.KEY_DOWN, this.onKey); } }

      private function onKey(e:KeyboardEvent):void {
         if (this._dbg != null) {
            this._dbg.input("key", e.keyCode, e.target);
            if (this._dbg.isDumpKey(e.keyCode)) {
               this._dbg.clearDump(); this._dbg.toggleDump();
               if (this._lastData != null) {
                  var q0:Object = (this._lastData.QuestsList != null && this._lastData.QuestsList.length > 0) ? this._lastData.QuestsList[0] : null;
                  this._dbg.dump("QuestsList[0] (G5)", q0);
                  this._dbg.dump("Quest[0].objectives[0] (G5)", (q0 != null && q0.objectives is Array && q0.objectives.length > 0) ? q0.objectives[0] : null);
                  this._dbg.dump("GeneralStatsList[0] (G6)", (this._lastData.GeneralStatsList != null && this._lastData.GeneralStatsList.length > 0) ? this._lastData.GeneralStatsList[0] : null);
                  this._dbg.dump("WorkshopsList[0]", (this._lastData.WorkshopsList != null && this._lastData.WorkshopsList.length > 0) ? this._lastData.WorkshopsList[0] : null);
               }
               return;
            }
         }
         this._list.handleKey(e.keyCode);
      }

      override public function ProcessUserEvent(param1:String, param2:Boolean):Boolean
      {
         if (!param2)
         {
            switch (param1)
            {
               case "XButton":   this.doMap();     return true;   // R / Xenon_X  (Show on Map)
               case "LShoulder": this.doSummary(); return true;   // C / Xenon_L1 (Summary)
               case "Accept":    this.doTrack();   return true;   // Enter / Xenon_A (Track)
            }
         }
         return false;
      }
   }
}
