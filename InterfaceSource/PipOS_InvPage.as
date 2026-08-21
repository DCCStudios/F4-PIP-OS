package
{
   import Shared.AS3.BSButtonHintData;
   import Shared.BGSExternalInterface;
   import pipos.PipList;
   import pipos.Theme;
   import pipos.VaultBoy;
   import pipos.Debug;
   import pipos.Ticker;
   import flash.display.DisplayObject;
   import flash.display.Graphics;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.geom.Point;
   import flash.text.TextField;

   // PIP-OS Inventory page, laid out to the M1 mockup (876x700, sidebar gutter): three columns
   // EQUIPMENT | CHARACTER+QUICK | LIST(headers)+CARD. Data plumbing is vanilla-equivalent
   // (DataObj.InvItems, engine-filled item-card InfoObj, SelectItem/ExamineItem/ItemDrop/SortItemList/
   // SetQuickkey/onInvItemSelection/updateItem3D). Single input path per action (ProcessUserEvent).
   public class PipOS_InvPage extends PipboyPage
   {
      // Exact 59-frame icon strip used by vanilla FavoritesMenu. DataObj.FavoritesList[i].FavIconType is the
      // authoritative frame number; embedding the vanilla symbol keeps modded favorite categories in parity.
      [Embed(source="../InterfaceAssets/FavoritesMenu.swf", symbol="FavoritesMenu_fla.HotkeyIcons_6")]
      private static var FavoritesIconClip:Class;
      private const DMG_TYPES:Array = ["BALLISTIC","ENERGY","RADIATION","POISON"];
      private static const CATS:Array = ["WEAPONS","APPAREL","AID","MISC","JUNK","MODS","AMMO"];
      private static const SLOTS:Array = ["HEAD","TORSO","LEFT ARM","RIGHT ARM","LEFT LEG","RIGHT LEG","UNDER ARMOR","OUTFIT","BACKPACK","WEAPON"];   // 0.0.60: WEAPON row (was the static PIP-BOY row)

      private var _chrome:Sprite;
      private var _title:TextField;
      private var _weight:TextField;
      private var _caps:TextField;
      private var _wIcon:Sprite;
      private var _chipBg:Sprite;   // WEIGHT/CAPS pill-chip backgrounds (static vector, drawn once in buildText)
      private var _subtabs:Sprite;
      private var _equip:Sprite;
      private var _char:Sprite;
      private var _vb:VaultBoy;
      private var _charCap:TextField;      // 0.0.60: figure-slot caption ("LIVE CAPTURE" only when 3D active)
      private var _list:PipList;
      private var _card:Sprite;
      private var _cardBg:Sprite;   // item-card border/background, faded with its contents during list expansion
      private var _quick:Sprite;
      private var _panels:Array = [];   // panel rects for the DEBUG clearance overlay

      private var _cardInfo:Array = [];
      private var _paperInfo:Object = {};
      private var _curTab:int = -1;
      private var _dmgIndex:int = 0;
      private var _invMap:Array = [];   // F1: filtered list-row -> original DataObj.InvItems index (folder headers map to -1)
      // FallUI/FIS tag FOLDERS: per-category OPEN memory (0.0.42: folders collapse by default). _folderState[tab] is
      // an Object {BUCKET_KEY:true} where presence == OPENED (absence == collapsed). Survives refreshes/re-sorts (it
      // lives on the page, not the list); resets on menu reopen (no cross-session store available from AS3).
      private var _folderState:Array = [];
      private var _listSelMem:Array = [];
      private var _listTopMem:Array = [];
      private var _listMemLoaded:Boolean = false;
      private var _builtTab:int = -1;
      // 0.0.38: runtime folder-grouping toggle (F4SE Menu Framework). Defaults to Theme.FOLDERS so absent
      // settings == 0.0.37 behavior; refreshed from root1.PipOS_settings.folders each data refresh (guarded).
      private var _foldersOn:Boolean = Theme.FOLDERS;
      // 0.0.43: weapon fire-rate display switch (F4SE Menu Framework). When root1.PipOS_settings.showRPM is true and
      // the stats push carries an rpm, weapon fire-rate rows show "RPM"/stats.rpm instead of "FIRE RATE"/firerate.
      // Defaults FALSE (absent setting == firerate behavior); refreshed each data refresh alongside folders (guarded).
      private var _showRPM:Boolean = false;
      private var _itemInfo:Object = null;   // P1-D: DLL-pushed root1.PipOS_iteminfo (name -> {w,v,a}); cached per refresh
      private var _dbg:Debug; private var _lastData:Pipboy_DataObj;
      private var _cardTitle:TextField; private var _cardDmg:TextField; private var _cardPairL:Array = []; private var _cardPairV:Array = []; private var _cardDesc:TextField;
      // 0.0.33 item-card fill (TASK B): DLL-pushed stats/mods drive the card. All fields POOLED (built once,
      // geometry baked in buildText); renderCard is UPDATE-ONLY (setText/textColor/visible + graphics).
      private var _cardSub:TextField;    // top-right subtitle (caliber / type / LEGENDARY / EQUIPPED)
      private var _cardLeg:TextField;    // legendary effect line (visible only when the row is legendary)
      private var _cardWt:TextField;     // WT chip value ; _cardCaps = CAPS chip value
      private var _cardCaps:TextField;
      private var _selRow:Object = null; // the currently-selected InvItems row (join source for the card)
      private var _itemStats:Object = null;  // root1.PipOS_itemstats (formID-string -> stats); cached per refresh
      private var _itemMods:Object = null;   // root1.PipOS_itemmods  (formID-string -> [modName,...])
      private var _hdr:Array = [];
      private var _hdrLabels:Array = [];   // header label strings (for sort-caret placement, no text-width read)

      // QOL-1: sortable column headers. Sort state is stored PER CATEGORY (7 tabs); nothing about the sort lives
      // in a TextField -- the order is applied to the item array before setItems, and the active-column caret is
      // drawn as vector graphics on a pooled markers layer (no geometry writes anywhere on the sort path).
      private var _sortCol:Array;          // per-tab active sort column index (-1 = engine/default order)
      private var _sortAsc:Array;          // per-tab sort direction
      private var _listBg:Sprite;          // list panel background in its OWN sprite (expand redraws just this)
      private var _listHdr:Sprite;         // header labels + divider + invtitle + sort caret, ABOVE the rows
      private var _hdrHitLayer:Sprite;     // pooled clickable header hit sprites
      private var _hdrHit:Array = [];      // header hit sprites (one per column)
      private var _hdrMark:Sprite;         // sort-caret markers layer (vector, graphics-only)
      private var _colGeom:Array = null;   // per-column geometry from PipList.columnGeom (header/data alignment)
      private var _invTitle:TextField;     // "INVENTORY . <CAT>[ . BY <KEY>]" list-panel heading (mockup)

      // QOL-4: expand/collapse the list. The pool is built for EXPANDED_ROWS up front so revealing rows is pure
      // visibility (no field creation on the click path); the reveal is animated by a container scrollRect + the
      // panel Shape redraw on a time-based Ticker (never per-field geometry).
      // 0.0.43 (in-game feedback): the inventory list is the most important surface -- show the MOST items
      // possible. The default (collapsed) window grows 12 -> 14 rows and the item card is shortened to just its
      // content bands (title/sub/WT-CAPS/legendary/stat-grid/flavor). The pool is still built for EXPANDED_ROWS
      // (20) up front (PipList maxRows), so 14 collapsed rows are pure visibility -- NO field creation on any
      // interaction path (the pre-sizing that keeps the taller default crash-law-legal).
      private static const COLLAPSED_ROWS:int = 15;   // 0.0.60: +1 visible row (card compacted again below)
      private static const EXPANDED_ROWS:int = 20;
      private var _expandBtn:Sprite;
      private var _expanded:Boolean = false;
      private var _expandT:Number = 0;     // 0 collapsed .. 1 expanded
      private var _expandDir:int = 0;      // +1 expanding, -1 collapsing
      private var _expandTicker:Ticker;
      private var _expH:Number = Theme.BB - Theme.BY;   // expanded panel height (full content column)
      private var _expand:BSButtonHintData;

      private var _subFields:Array = [];   // pooled category sub-tab label fields (built once in buildText)
      private var _subUL:Array = [];       // frozen underline rects {x,w} per sub-tab (no width read on update path)
      // A. QUICK ACCESS row (mockup #qa): 7 pooled boxes, each = hotkey number (corner) + vector type ICON
      // (center) + count badge (bottom). Boxes are POOLED (built once in buildText); refresh = text/visible/
      // graphics only. Icons redraw on a pooled mouse-transparent Shape layer; hit sprites drive click+hover.
      private var _qNum:Array = [];        // pooled hotkey-number fields (top-left corner)
      private var _qCount:Array = [];      // pooled count-badge fields (top-right corner)
      private var _qName:Array = [];       // 0.0.43: pooled SHORT-NAME labels (box bottom) so a filled slot is
                                           // identifiable without hovering (no real vanilla item icon is available)
      private var _qHit:Array = [];        // pooled per-box hit sprites (click select + hover tooltip)
      private var _qIcons:Sprite;          // pooled vector type-icon layer (graphics-only redraw)
      private var _qFavIcons:Array = [];   // pooled vanilla FavoritesMenu HotkeyIcons clips (frame = FavIconType)
      private var _qBox:Array = [];        // frozen per-box geometry {x,y,w,h,cx,cy} (no reads on update path)
      private var _favs:Array = null;      // root1.PipOS_favorites (12 slots {slot,formID,name,count,type}); cached
      private var _pendingFavFormID:String = null;   // QA click cross-category select: honoured on the next rebuild

      // B. Item mouseover TOOLTIP (single pooled widget). One mouse-transparent Sprite container repositioned by
      // .x/.y (a Sprite move never reformats text); its POOLED child TextFields keep fixed local geometry and only
      // update .text/.visible. Shown on inventory-row hover (via PipList.onHover) and QA-box hover; hidden on out.
      // 0.0.43 TOOLTIP REDESIGN (in-game feedback: values sat far from their labels). Compact panel: each value
      // hugs its label in a tight 2-column ("WT  13.1"), the box is narrow and sized to content, labels are
      // abbreviated (DMG/RATE/DR/RAD) so the value column starts close to the label. Pooled fields, update-only.
      private static const TIP_W:Number = 150;   // tooltip panel width (local units) -- was 244 (values too far)
      private static const TIP_PAD:Number = 8;
      private static const TIP_LCOL:Number = 42; // label column width; value column starts right after it
      private static const TIP_ROWS:int = 5;     // pooled label/value stat lines (WT, VAL, + up to 3 key stats)
      private var _tip:Sprite;             // container (mouseEnabled=false); .x/.y follow the cursor
      private var _tipName:TextField;      // full item NAME (uncut, 2-line reserved band)
      private var _tipSub:TextField;       // sub-type line
      private var _tipRowL:Array = [];     // pooled stat-line LEFT labels
      private var _tipRowV:Array = [];     // pooled stat-line RIGHT values
      private var _tipLineCount:int = 0;   // visible stat lines (drives the panel-bg height; not a geometry write)
      private var _equipVal:Array = [];   // 0.0.20: pooled per-slot equipped-item-name fields (DLL PipOS_equip push)

      // 16:9 grid geometry (mockup INV: cols 296 | 1fr(528) | 470, gap16). Derived from Theme.mx/ms so the
      // whole page re-flows from the single frame knob (FX/FY/MS). EQUIP | CENTER(figure+quick) | LIST+CARD.
      private var EQX:Number = Theme.CX;          // -8      equipment col left
      private var EQW:Number = Theme.ms(296);     // 236.8   equipment col width
      private var CCX:Number = Theme.mx(552);     // 241.6   center col left
      private var CCW:Number = Theme.ms(528);     // 422.4   center col width
      private var LX:Number  = Theme.mx(1096);    // 676.8   list col left
      private var LW:Number  = Theme.ms(470);     // 376     list col width
      // 0.0.43: list panel TALLER (was ms(438)=350.4) so 14 rows show by default; the shortened item card fills
      // the ~150px remaining below. cardTop = BY + _listH + gutter(10); card content bands are compacted to match.
      private var _listH:Number = Theme.ms(524);  // 419.2   0.0.60: taller list (15 rows); card compacts to fit below

      private var _inspect:BSButtonHintData;
      private var _drop:BSButtonHintData;
      private var _cycle:BSButtonHintData;
      private var _fav:BSButtonHintData;
      private var _sort:BSButtonHintData;

      // ============================================================================================
      // FULLSCREEN INSPECT OVERLAY (mockup #inspectlay). A POOLED, page-owned overlay layer: on activate it
      // dims the menu behind a translucent phosphor veil and presents the selected item LARGE at centre --
      // a big title, a legendary badge (subtle pulse), a Stats panel (left) and a Current Mods panel (right),
      // plus a keybar (W PREV / S NEXT / WHEEL ZOOM / R EXIT). We have NO live 3D item capture (the DLL 3D
      // feature is the character, not items), so the centre is an honest large VECTOR emblem, not a fake fly-in.
      //
      // CRASH LAW: every TextField below is created ONCE with baked geometry (autoSize="none") in buildInspect
      // (a pool builder called from buildText). enter/exit/cycle/zoom/tick handlers are UPDATE-ONLY: they touch
      // only .text/.textColor/.visible + graphics + Sprite-CONTAINER .x/.y/.alpha/.scale (never TextField geom).
      private static const INS_STAT_ROWS:int = 8;   // pooled stat lines (weapon 4 + AMMO/WT/VAL; apparel 3 + WT/VAL)
      private static const INS_MOD_ROWS:int = 12;   // pooled mod-name lines (contract caps installed mods at 16)
      private var _insLay:Sprite;          // overlay root (topmost page child); .alpha faded, .visible gated; veil+panels on its own graphics
      private var _insEmblem:Sprite;       // centred vector item emblem; WHEEL scales this container (.scale)
      private var _insLeg:Sprite;          // legendary badge container (hidden for non-legendaries)
      private var _insBadge:Sprite;        // the pulsing badge box (its .alpha oscillates while inspecting)
      private var _insKeys:Sprite;         // static keybar (built once via Theme.keycap)
      private var _insTitle:TextField;     // big item title (top-centre)
      private var _insLegText:TextField;   // legendary effect line (beside the badge)
      private var _insStatsHdr:TextField;  // "STATS" panel header
      private var _insModsHdr:TextField;   // "CURRENT MODS" panel header
      private var _insStatL:Array = [];    // pooled stat-line LEFT labels
      private var _insStatV:Array = [];    // pooled stat-line RIGHT values
      private var _insModRows:Array = [];  // pooled mod-name lines
      private var _inspecting:Boolean = false;
      private var _insIsLeg:Boolean = false;  // current item legendary? (drives the badge pulse)
      private var _insZoom:Number = 1;        // emblem scale (WHEEL); reset to 1 on enter
      private var _insFade:Number = 0;        // 0 hidden .. 1 shown (container alpha, smoothstepped)
      private var _insFadeDir:int = 0;        // +1 fading in, -1 fading out, 0 settled
      private var _insPulse:Number = 0;       // legendary-badge pulse phase (seconds)
      private var _insTicker:Ticker;          // drives the fade + the badge pulse (time-based, 30fps-safe)

      public function PipOS_InvPage()
      {
         super();
         _TabNames = new Array("$InventoryCategoryWeapons","$InventoryCategoryApparel","$InventoryCategoryAid","$InventoryCategoryMisc","$InventoryCategoryJunk","$InventoryCategoryMods","$InventoryCategoryAmmo");
         this._sortCol = [-1, -1, -1, -1, -1, -1, -1];   // one per category tab; -1 = engine order
         this._sortAsc = [false, false, false, false, false, false, false];
         this._folderState = [{}, {}, {}, {}, {}, {}, {}];   // per-category folder collapse memory (empty == all open)
         this._listSelMem = [-1, -1, -1, -1, -1, -1, -1];
         this._listTopMem = [0, 0, 0, 0, 0, 0, 0];
         this.buildPanels();
         this._dbg = new Debug("INV"); addChild(this._dbg);
         Theme.life("IV.c");   // 0.0.52 forensics: ctor completed (control for the STAT trail)
      }

      override protected function PopulateButtonHintData():*
      {
         // 0.0.60 KEY FIX (field-observed swap): the engine routes KEYBOARD keys by its own control map, not
         // by our PCKey display strings -- keyboard X fires the R3/inspect user event and R is the drop key
         // (vanilla InvPage ground truth: InspectButton PCKey "X", DropButton PCKey "R"). Displaying R=INSPECT/
         // X=DROP therefore read swapped in game. Labels now match the engine: X = INSPECT, R = DROP; R is also
         // claimed directly in onKey (the engine's R->drop dispatch was not reaching this page at all).
         this._inspect = new BSButtonHintData("$INSPECT","X","PSN_R3","Xenon_R3",1,this.doInspect);
         this._drop    = new BSButtonHintData("$DROP","R","PSN_X","Xenon_X",1,this.doDrop);
         this._cycle   = new BSButtonHintData("$CYCLE DAMAGE","C","PSN_L1","Xenon_L1",1,this.doCycleDamage);
         this._fav     = new BSButtonHintData("$FAV","Q","PSN_R1","Xenon_R1",1,this.doFav);
         this._sort    = new BSButtonHintData("$SORT","Z","PSN_L3","Xenon_L3",1,this.doSort);
         // QOL-4: expand/collapse the inventory list. Reachable via the E hotkey (onKey) + the on-panel button.
         // 0.0.33 audit fix A3: EXPAND is now KEYBOARD-ONLY -- no pad glyph. The 0.0.32 chip advertised PSN_L1/
         // Xenon_L1, the SAME pad control _cycle (Cycle Damage) already claims (LShoulder -> doCycleDamage in
         // ProcessUserEvent), so the L1 glyph on the EXPAND chip actually fired Cycle Damage (a misleading
         // control). Passing empty pad-button names drops the pad glyph entirely; the "E" key label is honest
         // (keyboard/mouse reach it), and no pad control is falsely advertised.
         this._expand  = new BSButtonHintData("$EXPAND","E","","",1,this.doExpand);
         // T PERK CHART chip is intentionally NOT added here. The shell already pushes its dynamic
         // GridViewButton (PCKey T, text "Grid View"/"LEVELUP (n)", flashing, callback -> ShowPerksMenu)
         // onto every page's buttonHintDataV at load; the chrome relabels its "Grid View" text to
         // "PERK CHART" for display. This keeps exactly ONE T chip with the shell's live LEVELUP state.
         _buttonHintDataV.push(this._inspect);
         _buttonHintDataV.push(this._drop);
         _buttonHintDataV.push(this._cycle);
         _buttonHintDataV.push(this._fav);
         _buttonHintDataV.push(this._sort);
         _buttonHintDataV.push(this._expand);
      }

      override protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.Inventory; }
      private function sfx(ev:String):void { BGSExternalInterface.call(this.codeObj, "PlaySound", ev); }

      // CTOR: panels/sprites/graphics ONLY. NO TextField creation (Theme.tf sets autoSize/format which
      // formats against a font context absent during ProcessLoadQueue construction -> FindFont NULL CTD).
      private function buildPanels():void
      {
         var P:Number = Theme.PAD;
         var gh:Number = Theme.BB - Theme.BY;                 // grid height
         var cardTop:Number = Theme.BY + this._listH + 10;    // list panel + 10 gutter, then the (short) item card
         this._chrome = new Sprite(); addChild(this._chrome);
         var g:* = this._chrome.graphics;
         Theme.panelR(g, this._panels, this.EQX, Theme.BY, this.EQW, gh);                 // EQUIPMENT
         // CENTER column: NO panel/box (mockup #figurebox has no border/background -- the character floats).
         // The center holds only the floating figure + LIVE CAPTURE caption + QUICK ACCESS row (drawn below).
         // LIST panel is drawn into its OWN sprite (_listBg) so the expand animation can redraw only it
         // (graphics-only) without disturbing the other panels/headers. Its rect is still registered for debug.
         this._panels.push({ x:this.LX, y:Theme.BY, w:this.LW, h:this._listH });
         // ITEM CARD owns a separate graphics layer so expand/collapse can fade the whole window, including
         // its border, without redrawing the shared chrome Graphics object.
         this._cardBg = new Sprite(); addChild(this._cardBg);
         Theme.panel(this._cardBg.graphics, this.LX, cardTop, this.LW, Theme.BB - cardTop);
         this._panels.push({ x:this.LX, y:cardTop, w:this.LW, h:Theme.BB - cardTop });
         this._wIcon = new Sprite(); addChild(this._wIcon);
         this._subtabs = new Sprite(); this._subtabs.y = Theme.SUB_Y; addChild(this._subtabs);
         this._equip = new Sprite(); this._equip.x = this.EQX + P; this._equip.y = Theme.BY + P; addChild(this._equip);
         this._char = new Sprite(); this._char.x = this.CCX; this._char.y = Theme.BY; addChild(this._char);
         // P2: VaultBoy composites its figure centered about its OWN local x=0 (see VaultBoy.composite), so
         // x = CCW/2 places the figure center on the character-column midline (was CCW/2 - 95 = left of center).
         try { this._vb = new VaultBoy(400); this._vb.x = this.CCW / 2; this._vb.y = 34; this._char.addChild(this._vb); } catch (e:Error) { this._vb = null; }
         var cg:* = this._char.graphics;
         cg.beginFill(Theme.PHOS, 0.10); cg.drawEllipse(this.CCW / 2 - 55, gh - 118, 110, 18); cg.endFill();
         this._quick = new Sprite(); this._quick.x = this.CCX; this._quick.y = Theme.BB - 84; addChild(this._quick);
         // List panel background in its own sprite (below rows + headers) so expand redraws only this.
         this._listBg = new Sprite(); addChild(this._listBg); this.drawListBg(this._listH);
         this._list = new PipList(this.LW - 2 * P, 25, COLLAPSED_ROWS, EXPANDED_ROWS);
         this._list.x = this.LX + P; this._list.y = Theme.BY + 44;
         this._list.onSelectionChange = this.onListSel; this._list.onItemPress = this.onListPress; this._list.playSound = this.sfx;
         this._list.onHover = this.onListHover;   // B: row hover -> item tooltip (pure callback; no fields/geometry)
         this._list.onFolderToggle = this.onFolderToggle;   // FIS folders: header click -> collapse toggle (pure callback)
         this._list.onRowContext = this.onRowContext;       // 0.0.61: right-click -> context menu
         this._list.onViewportChange = this.onListViewport;
         // 4-column config is STABLE (NAME|AMMO|WT|VAL); set here (font-free) so columnGeom() can align headers.
         this._list.columns = [{w:0,align:"left"},{w:64,align:"left"},{w:40,align:"right"},{w:44,align:"right"}]; this._list.optCol = 1; this._list.optOn = false;
         this._colGeom = this._list.columnGeom();
         addChild(this._list);
         // Header layers ABOVE the rows: labels/divider/invtitle/sort-caret (_listHdr, caret on _hdrMark), then the
         // clickable header hit sprites (_hdrHitLayer), then the expand button. All font-free here (text -> buildText).
         this._listHdr = new Sprite(); addChild(this._listHdr);
         this._hdrMark = new Sprite(); this._hdrMark.mouseEnabled = false; this._hdrMark.mouseChildren = false; this._listHdr.addChild(this._hdrMark);
         this._hdrHitLayer = new Sprite(); addChild(this._hdrHitLayer); this.buildHeaderHits();
         // 0.0.59: raised from BY+6 to BY-2 -- at BY+6 the 18px glyph sat straight over the right-aligned VAL
         // column header (BY+16..). At BY-2 it ends exactly where VAL starts and only overlaps the empty right
         // end of the INVENTORY title band (button added later == on top, so its clicks are unaffected).
         this._expandBtn = new Sprite(); this._expandBtn.x = this.LX + this.LW - 26; this._expandBtn.y = Theme.BY - LIST_HEADROOM + 7; this._expandBtn.buttonMode = true; this._expandBtn.addEventListener(MouseEvent.MOUSE_DOWN, this.onExpandBtn); addChild(this._expandBtn); this.drawExpandGlyph();   // 6px lower per field layout review
         this._card = new Sprite(); this._card.x = this.LX + P; this._card.y = cardTop + P; addChild(this._card);
         this._card.scrollRect = new Rectangle(0, 0, this.LW - 2 * P, (Theme.BB - cardTop) - 2 * P);
         addEventListener(Event.ADDED_TO_STAGE, this.onPageStage);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onPageUnstage);
      }

      // BUILD-WINDOW (called once from buildPanels): pooled clickable header hit sprites over each column, aligned
      // to the same geometry as the data columns. Font-free (graphics + listeners only). No dead controls: every
      // header sorts (the AMMO/opt hit is disabled off-weapons by layoutHeader, matching its hidden data column).
      private function buildHeaderHits():void
      {
         if (this._colGeom == null) { return; }
         for (var i:int = 0; i < this._colGeom.length && i < 4; i++) {
            var geo:Object = this._colGeom[i];
            var hh:Sprite = new Sprite();
            hh.graphics.beginFill(0x000000, 0.004); hh.graphics.drawRect(this._list.x + Number(geo.x), Theme.BY + 12, Number(geo.w), 24); hh.graphics.endFill();
            hh.name = "hc" + i; hh.buttonMode = true; hh.addEventListener(MouseEvent.MOUSE_DOWN, this.onHeaderClick);
            this._hdrHitLayer.addChild(hh); this._hdrHit.push(hh);
         }
      }

      // 0.0.62: the list panel now extends UPWARD by LIST_HEADROOM so the EXPAND button has its own clean strip
      // above the "INVENTORY · <CAT>" title (was overlapping the VAL header / title). Rows/headers are unchanged.
      private static const LIST_HEADROOM:Number = 16;   // 0.0.65: was 20 -- top came down ~4px (expand button follows)
      // Graphics-only (safe on any path): redraw the list panel background at height h (extended up by the headroom).
      private function drawListBg(h:Number):void
      {
         var g:* = this._listBg.graphics; g.clear();
         Theme.panel(g, this.LX, Theme.BY - LIST_HEADROOM, this.LW, h + LIST_HEADROOM);
      }

      // Graphics-only: expand/collapse glyph (font-independent) on the list-panel corner button.
      private function drawExpandGlyph():void
      {
         var g:* = this._expandBtn.graphics; g.clear();
         g.beginFill(0x000000, 0.004); g.drawRect(-3, -3, 24, 24); g.endFill();   // generous hit pad
         Theme.frameRect(g, 0, 0, 18, 18, Theme.PHOS, 0.5);
         Theme.fillLine(g, 4, 4, 14, 14, Theme.PHOS_BRIGHT, 1, 1.4);
         if (!this._expanded) {   // outward corner arrows == expand
            Theme.fillLine(g, 4, 4, 9, 4, Theme.PHOS_BRIGHT, 1, 1.4); Theme.fillLine(g, 4, 4, 4, 9, Theme.PHOS_BRIGHT, 1, 1.4);
            Theme.fillLine(g, 14, 14, 9, 14, Theme.PHOS_BRIGHT, 1, 1.4); Theme.fillLine(g, 14, 14, 14, 9, Theme.PHOS_BRIGHT, 1, 1.4);
         } else {                 // inward corner arrows == collapse
            Theme.fillLine(g, 9, 4, 4, 4, Theme.PHOS_BRIGHT, 1, 1.4); Theme.fillLine(g, 4, 4, 4, 9, Theme.PHOS_BRIGHT, 1, 1.4);
            Theme.fillLine(g, 9, 14, 14, 14, Theme.PHOS_BRIGHT, 1, 1.4); Theme.fillLine(g, 14, 14, 14, 9, Theme.PHOS_BRIGHT, 1, 1.4);
         }
      }

      // ON-STAGE ONLY (via ensureText): ALL TextField creation + text.
      private function buildText():void
      {
         var P:Number = Theme.PAD;
         var gh:Number = Theme.BB - Theme.BY;
         // No standalone page title (mockup: the sidebar shows the active page). Keep the pooled field, hidden.
         this._title = Theme.mk(this, 22, Theme.PHOS_BRIGHT, true); this._title.visible = false; Theme.setText(this._title, "INVENTORY");
         // WEIGHT / CAPS readouts sit at the right of the sub-tab strip (mockup .subtabs .chips), not a bar.
         // FIXED autoSize="none" right-aligned boxes: the text right-justifies to a CONSTANT right edge (CAPS ->
         // INFO_R), so the refresh path needs no `.x`/`.width` write. Geometry is baked here BEFORE text; icons
         // draw at the fixed box-left (x-18). Boxes are snug so the right-aligned value stays adjacent to its icon.
         // WEIGHT / CAPS as bordered PILL CHIPS (mockup .subtabs .chips): 1px --line border, radius 6, --panel bg,
         // icon + value. Chip boxes are STATIC vector (drawn once here into _chipBg); the value fields are FIXED
         // autoSize="none" right-aligned boxes (refresh = setText/textColor only, no geometry write). Icons redraw
         // per refresh into _wIcon (graphics-only) at positions derived from the fixed field x (reads only).
         var chPad:Number = 9; var chIcon:Number = 16; var chH:Number = 24; var chGap:Number = 14;
         var capsW:Number = 68; var weightW:Number = 104;
         var capsX:Number = Theme.INFO_R - chPad - capsW;
         var capsChipL:Number = capsX - chIcon - chPad;
         var weightX:Number = (capsChipL - chGap) - chPad - weightW;
         var weightChipL:Number = weightX - chIcon - chPad;
         var chipY:Number = Theme.SUB_Y - 1;
         var wChipW:Number = weightW + chIcon + 2 * chPad; var cChipW:Number = capsW + chIcon + 2 * chPad;
         this._chipBg = new Sprite(); addChild(this._chipBg);
         var cbg:* = this._chipBg.graphics;
         cbg.beginFill(Theme.PANEL, 0.82); cbg.drawRoundRect(weightChipL, chipY, wChipW, chH, 6, 6); cbg.endFill();
         Theme.frameRect(cbg, weightChipL + 0.5, chipY + 0.5, wChipW - 1, chH - 1, Theme.LINE, 0.42);
         cbg.beginFill(Theme.PANEL, 0.82); cbg.drawRoundRect(capsChipL, chipY, cChipW, chH, 6, 6); cbg.endFill();
         Theme.frameRect(cbg, capsChipL + 0.5, chipY + 0.5, cChipW - 1, chH - 1, Theme.LINE, 0.42);
         addChild(this._wIcon);   // lift the weight/caps icons above the chip fill
         this._caps = Theme.mk(this, 12, Theme.PHOS_BRIGHT, false, "right"); this._caps.autoSize = "none"; this._caps.width = capsW; this._caps.height = 18; this._caps.x = capsX; this._caps.y = chipY + 5; Theme.setText(this._caps, "CAPS --");
         this._weight = Theme.mk(this, 12, Theme.PHOS_BRIGHT, false, "right"); this._weight.autoSize = "none"; this._weight.width = weightW; this._weight.height = 18; this._weight.x = weightX; this._weight.y = chipY + 5; Theme.setText(this._weight, "WEIGHT --/--");
         this.buildSubtabs();
         Theme.heading(this._equip, 0, 0, "EQUIPMENT");
         var eqW:Number = this.EQW - 2 * P;
         // Mockup #equip .row: 92px slot-label column + item name on the SAME row, ~30px rows, thin bottom divider,
         // slot label 9.5px dim uppercase. slotCol = ms(92) local; single-line rows (label | name side by side).
         var slotCol:Number = 74;
         var rowPitch:Number = 30;
         for (var si:int = 0; si < SLOTS.length; si++)
         {
            var sy:Number = 30 + si * rowPitch;
            var sl:TextField = Theme.mk(this._equip, 11, Theme.PHOS_DIM, true); sl.x = 0; sl.y = sy + 4; Theme.setText(sl, SLOTS[si]);
            // P1-B: clip the equipped-item name to the panel via an auto-sized field + scrollRect viewport
            // (SetWidth-free; applyEquip only ever re-sets .text, so the clip holds with no FindFont vector).
            var sv:TextField = Theme.mk(this._equip, 13, Theme.PHOS, false); sv.x = slotCol; sv.y = sy + 2; sv.scrollRect = new Rectangle(0, 0, eqW - slotCol, 17); Theme.setText(sv, "-"); this._equipVal.push(sv);
            this._equip.graphics.beginFill(Theme.LINE, 0.14); this._equip.graphics.drawRect(0, sy + rowPitch - 3, eqW, 1); this._equip.graphics.endFill();   // 0.0.60: filled divider (stroke elimination)
         }
         // 0.0.60: equip-change PULSE layer -- a short bright bar at each row's left edge that flares when that
         // slot's item changes (live feedback for equipping from the list). Graphics-only; faded in onCharPoll.
         this._eqPulseLayer = new Shape(); this._equip.addChild(this._eqPulseLayer);
         this._charCap = Theme.mk(this._char, 9, Theme.PHOS_DIM, false, "center"); this._charCap.autoSize = "none"; this._charCap.width = this.CCW - 2 * P; this._charCap.multiline = true; this._charCap.wordWrap = true; this._charCap.x = P; this._charCap.y = gh - 150; Theme.setText(this._charCap, "");   // 0.0.60: caption managed by onCharPoll ("LIVE CAPTURE" only when the 3D figure is live)
         // Parity #qa: the QUICK ACCESS label sits BELOW the icon-box row (mockup order = slots then label). Boxes
         // live in _quick (top at Theme.BB - 84, height 44 -> bottom Theme.BB - 40); the label sits ~6px under them.
         var ql:TextField = Theme.mk(this, 10, Theme.PHOS_DIM, true, "center"); ql.autoSize = "none"; ql.width = this.CCW; ql.x = this.CCX; ql.y = Theme.BB - 34; var qf:* = ql.defaultTextFormat; qf.letterSpacing = 1.6; ql.defaultTextFormat = qf; Theme.setText(ql, "QUICK ACCESS");
         var CWID0:Number = this.LW - 2 * Theme.PAD;   // 352 card interior width
         // TASK B item card (mockup #itemcard). FIXED geometry baked here on fresh empty fields; renderCard is
         // update-only. The card reads its data from the DLL push (PipOS_itemstats/itemmods/iteminfo), NOT from
         // the engine _cardInfo (which arrives empty). Vertical bands are RESERVED (never moved per item) so a
         // wrapping title or a legendary line never shifts the fields below (moving a text-bearing field on the
         // selection path == the SetY/SetWidth -> FindFont crash class). Bands: title 0..42 | chips y44 |
         // legendary y68 | stat grid y88 (2 rows) | flavor y134.
         // TITLE: 2-line region (mockup legendary name wraps) + top-right SUB, so both are fixed-box.
         // 0.0.43 SHORT CARD: bands compacted (title 0..30 | chips y32 | legendary y54 | stat grid y70 (pitch 17) |
         // flavor y106) so the whole card fits ~150px and the list panel above can be taller (more visible rows).
         // 0.0.60 SHORTER CARD (round 2, user ask): bands re-compacted -- title 0..24 | chips y24 | legendary y46 |
         // stat grid y64 (pitch 15) | NO flavor band (the derived line moved to the hover tooltip; the field stays
         // pooled+hidden). Frees ~25px, giving the list its 15th collapsed row.
         this._cardTitle = Theme.mk(this._card, 16, Theme.PHOS_BRIGHT, true); this._cardTitle.autoSize = "none"; this._cardTitle.multiline = true; this._cardTitle.wordWrap = true; this._cardTitle.width = CWID0 - 96; this._cardTitle.height = 24; this._cardTitle.x = 0; this._cardTitle.y = 0; Theme.glow(this._cardTitle, Theme.PHOS_BRIGHT, 1);
         this._cardSub = Theme.mk(this._card, 10, Theme.PHOS_DIM, true, "right"); this._cardSub.autoSize = "none"; this._cardSub.width = 150; this._cardSub.height = 14; this._cardSub.x = CWID0 - 150; this._cardSub.y = 4; this._cardSub.visible = false;
         // Legacy damage-mode field parked (kept for pool stability; damage type is now folded into the stat
         // label "DAMAGE . <MODE>"). renderCard keeps it hidden.
         this._cardDmg = Theme.mk(this._card, 11, Theme.WARN, true); this._cardDmg.autoSize = "none"; this._cardDmg.width = 120; this._cardDmg.height = 16; this._cardDmg.x = 0; this._cardDmg.y = 24; this._cardDmg.visible = false;
         // WT / CAPS chip VALUE fields (the chip boxes + icons are drawn in renderCard graphics at these fixed x).
         this._cardWt = Theme.mk(this._card, 12, Theme.PHOS_BRIGHT, true); this._cardWt.autoSize = "none"; this._cardWt.width = 42; this._cardWt.height = 18; this._cardWt.x = 28; this._cardWt.y = 26; this._cardWt.visible = false;
         this._cardCaps = Theme.mk(this._card, 12, Theme.PHOS_BRIGHT, true); this._cardCaps.autoSize = "none"; this._cardCaps.width = 42; this._cardCaps.height = 18; this._cardCaps.x = 112; this._cardCaps.y = 26; this._cardCaps.visible = false;
         // LEGENDARY effect line (WARN, visible only when the row is legendary; sparkle drawn in graphics at x6).
         this._cardLeg = Theme.mk(this._card, 11, Theme.WARN, false); this._cardLeg.autoSize = "none"; this._cardLeg.multiline = true; this._cardLeg.wordWrap = true; this._cardLeg.width = CWID0 - 16; this._cardLeg.height = 16; this._cardLeg.x = 16; this._cardLeg.y = 46; this._cardLeg.visible = false;
         // STAT-PAIR grid: 4 pairs used (2x2), 6 pooled for headroom. Value fields are FIXED-width right-aligned
         // boxes (right edge at colX + CWID/2 - 8), so renderCard sets ONLY .text; labels are auto-size LEFT
         // (proven 0.0.32 pattern, first-texted after the font resolves). CARD_GY must match renderCard.
         var CARD_GY:Number = 64;   // 0.0.60: stat grid top (must match renderCard's gy)
         for (var cpi:int = 0; cpi < 6; cpi++) {
            var colX0:Number = (cpi % 2 == 0) ? 0 : CWID0 / 2; var rowY0:Number = CARD_GY + Math.floor(cpi / 2) * 15;
            var lt0:TextField = Theme.mk(this._card, 11, Theme.PHOS_DIM, false); lt0.x = colX0 + 10; lt0.y = rowY0; lt0.visible = false; this._cardPairL.push(lt0);
            var vt0:TextField = Theme.mk(this._card, 12, Theme.PHOS_BRIGHT, true, "right"); vt0.autoSize = "none"; vt0.width = CWID0 / 2 - 68; vt0.height = 16; vt0.x = colX0 + 60; vt0.y = rowY0; vt0.visible = false; this._cardPairV.push(vt0);
         }
         // 0.0.60: flavor band RETIRED from the card (space went to the 15th list row); field stays pooled+hidden
         // for pool stability. The derived line (aid effect / ammo used-by) still shows in the hover tooltip.
         this._cardDesc = Theme.mk(this._card, 11, Theme.PHOS_DIM, false); this._cardDesc.autoSize = "none"; this._cardDesc.multiline = true; this._cardDesc.wordWrap = true; this._cardDesc.width = CWID0; this._cardDesc.height = 20; this._cardDesc.x = 0; this._cardDesc.y = CARD_GY + 2 * 15 + 2; this._cardDesc.visible = false;
         var hcols:Array = [["NAME","left"],["AMMO","left"],["WT","right"],["VAL","right"]];
         var innerWd:Number = this.LW - 2 * Theme.PAD;   // 352
         // Parity fix C1: header cells are placed at the SAME list-local x/width as the DATA columns (from
         // PipList.columnGeom, offset by list.x), so each label sits directly over its values -- was ~10px off,
         // and NAME was missing the marker-gutter offset. Geometry is baked on the FRESH field BEFORE text; the
         // set is fixed for the life of the page (layoutHeader only toggles AMMO visibility, never moves a field).
         var geo:Array = this._colGeom; var hy0:Number = Theme.BY + 16;
         for (var hi:int = 0; hi < 4 && geo != null && hi < geo.length; hi++) {
            var gx:Number = this._list.x + Number(geo[hi].x); var gw:Number = Number(geo[hi].w);
            var ht:TextField = Theme.mk(this._listHdr, 10, Theme.PHOS_DIM, true, String(hcols[hi][1])); ht.autoSize = "none"; var htf:* = ht.defaultTextFormat; htf.letterSpacing = 1; ht.defaultTextFormat = htf;
            ht.width = gw; ht.height = 20; ht.x = gx; ht.y = hy0;   // ALL geometry FIRST (fresh empty field)
            if (hi == 1) { ht.visible = false; }   // AMMO hidden by default (non-weapons); layoutHeader shows it on Weapons
            Theme.setText(ht, String(hcols[hi][0]));   // text LAST
            ht.scrollRect = new Rectangle(0, 0, gw, 20);   // clip to column; scrollRect does NOT call SetWidth/SetY
            this._hdr.push(ht); this._hdrLabels.push(String(hcols[hi][0]));
         }
         var hyd:Number = Theme.BY + 34; var hxd:Number = this.LX + Theme.PAD;
         Theme.fillLine(this._listHdr.graphics, hxd, hyd, hxd + innerWd, hyd, Theme.LINE, 0.3);
         // invtitle: "INVENTORY . <CAT>[ . BY <KEY>]" (mockup list-panel heading; the sort suffix shows the active
         // column, e.g. ". BY WEIGHT"). Compact band in the panel-top padding above the headers. Geometry-before-text.
         this._invTitle = Theme.mk(this._listHdr, 10, Theme.PHOS_BRIGHT, true); this._invTitle.autoSize = "none"; this._invTitle.width = innerWd; this._invTitle.height = 14; this._invTitle.x = hxd; this._invTitle.y = Theme.BY + 1;   // 0.0.46: bright "INVENTORY . <CAT>" heading (mockup)
         var itf:* = this._invTitle.defaultTextFormat; itf.letterSpacing = 1.2; this._invTitle.defaultTextFormat = itf; Theme.setText(this._invTitle, "INVENTORY");
         // QUICK ACCESS (mockup #qa): a centered row of 7 boxes -- hotkey number (top-left) + count (top-right) +
         // vector type ICON (upper-centre) + SHORT NAME (bottom). Boxes are POOLED here; renderQuick is update-only
         // (text/visible +
         // icon-layer graphics). Box outlines are static graphics; the icon layer + hit sprites are added so the
         // icon glyphs sit under the (mouse-transparent) numbers/counts and the hit sprites catch click+hover.
         // Mockup .qslot = 56x56 -> local ~44.8 (box 44); gap 8 -> ~6.4 (gap 6); radius 6 -> ~5; border var(--line) 0.38.
         var qn7:int = 7; var qcw:Number = 44; var qch:Number = 44; var qgap:Number = 6;
         var qtot:Number = qn7 * qcw + (qn7 - 1) * qgap; var qstart:Number = (this.CCW - qtot) / 2;
         var qg:* = this._quick.graphics;
         this._qIcons = new Sprite(); this._qIcons.mouseEnabled = false; this._qIcons.mouseChildren = false; this._quick.addChild(this._qIcons);
         for (var qi:int = 0; qi < qn7; qi++) {
            var qx:Number = qstart + qi * (qcw + qgap); var qy:Number = 0;
            qg.beginFill(Theme.PANEL, 0.82); qg.drawRoundRect(qx, qy, qcw, qch, 5, 5); qg.endFill();
            Theme.frameRect(qg, qx + 0.5, qy + 0.5, qcw - 1, qch - 1, Theme.LINE, 0.4);
            // 0.0.43: icon centred slightly HIGH so a SHORT-NAME label fits along the box bottom.
            this._qBox.push({ x:qx, y:qy, w:qcw, h:qch, cx:(qx + qcw / 2), cy:(qy + qch / 2 - 5) });
            var qfav:MovieClip = new FavoritesIconClip() as MovieClip; qfav.mouseEnabled = false; qfav.mouseChildren = false;
            qfav.x = qx + qcw / 2; qfav.y = qy + qch / 2 - 5; qfav.scaleX = 0.46; qfav.scaleY = 0.46; qfav.visible = false;
            this._quick.addChild(qfav); this._qFavIcons.push(qfav);
            var qnum:TextField = Theme.mk(this._quick, 9, Theme.PHOS_DIM, true); qnum.x = qx + 4; qnum.y = qy + 2; Theme.setText(qnum, String(qi + 1)); this._qNum.push(qnum);
            // 0.0.43: count badge at the box TOP-RIGHT (right-aligned, opposite the hotkey number) so the box
            // bottom is free for the short-name label below.
            var qct:TextField = Theme.mk(this._quick, 10, Theme.PHOS_BRIGHT, true, "right"); qct.autoSize = "none"; qct.width = qcw - 8; qct.height = 12; qct.x = qx + 4; qct.y = qy + 2; qct.visible = false; this._qCount.push(qct);
            // 0.0.43 SHORT NAME (box bottom, centred): identifies a filled slot at a glance without the hover popup.
            var qnm:TextField = Theme.mk(this._quick, 8, Theme.PHOS_DIM, true, "center"); qnm.autoSize = "none"; qnm.width = qcw - 4; qnm.height = 12; qnm.x = qx + 2; qnm.y = qy + qch - 13; qnm.visible = false; this._qName.push(qnm);
            var qhit:Sprite = new Sprite();
            qhit.graphics.beginFill(0x000000, 0.004); qhit.graphics.drawRect(qx, qy, qcw, qch); qhit.graphics.endFill();
            qhit.name = "q" + qi; qhit.buttonMode = true;
            qhit.addEventListener(MouseEvent.MOUSE_DOWN, this.onQAClick);
            qhit.addEventListener(MouseEvent.ROLL_OVER, this.onQAOver);
            qhit.addEventListener(MouseEvent.ROLL_OUT, this.onQAOut);
            this._quick.addChild(qhit); this._qHit.push(qhit);
         }
         this.buildTooltip();
         this.buildContextMenu();   // 0.0.61: pooled right-click menu (built once, on-stage)
         // 0.0.31: the list column config is STABLE (4 columns: NAME | AMMO | WT | VAL) so PipList can pool its
         // rows ONCE at fixed geometry. The AMMO column is OPTIONAL (optCol=1): on non-weapon tabs layoutHeader
         // flips _list.optOn=false, and PipList hides AMMO + widens the NAME viewport via scrollRect ONLY -- no
         // geometry write on the tab-change path. itemAdapter always returns 4 cols (AMMO empty off-weapons).
         // (columns/optCol are assigned in buildPanels so columnGeom can align the headers; here only optOn.)
         if (this._list != null) { this._list.optOn = (this._curTab == 0); }
         this.applyEquip();   // 0.0.20: pick up an already-present DLL equip push (open-race safe; refreshed on change)
         // 0.0.33 audit fix A2: force PipList.buildPool NOW, inside this proven-safe on-stage build window
         // (buildText runs from onPageStage/ADDED_TO_STAGE or the first onPipboyChangeEvent -- both non-
         // interaction contexts, the same window that safely creates every field above). PipList builds its
         // pool lazily on the FIRST render(); several new interaction entry points (onWheel, doExpand ->
         // setRenderRows, selectIndexSilent) call render() directly, so without this a first render could fire
         // the pool build INSIDE interaction dispatch (the geometry-write-on-fresh-field FindFont crash class).
         // Forcing the build here guarantees _pooled == true before any interaction can reach the list, so no
         // handler can ever trigger a first build. render() on empty entries is a no-op (hides all slots).
         if (this._list != null && stage != null) { this._list.render(); }
         this.buildInspect();   // pooled fullscreen inspect overlay (topmost page child; hidden until activated)
         // 0.0.57: per-page keybar RESTORED (exonerated -- the radio/data CTDs were the font-donor unload, fixed
         // by the chrome page-def preloader). Vanilla hint bar is now hidden persistently by the chrome.
         Theme.keybar(this, [{key:"ESC",label:"BACK"},{key:"X",label:"INSPECT"},{key:"R",label:"DROP"},{key:"C",label:"CYCLE DAMAGE"},{key:"Q",label:"FAV"},{key:"Z",label:"SORT"},{key:"E",label:"EXPAND"},{key:"T",label:"PERK CHART"}], Theme.my(830));   // 0.0.60: X=INSPECT / R=DROP (engine key map; see hint note)
         // NOTE (0.0.47): the per-page custom keybar was REMOVED. The vanilla shell's button-hint bar is still
         // visible in game and already shows the correct per-page prompts (incl. the dynamic T "LEVEL UP (n)" /
         // perk-chart state), so our own bar just duplicated it. Restyling/repositioning the vanilla bar to the
         // mockup is the follow-up; this also isolates whether Theme.keybar caused the Radio/STAT build crashes.
      }

      private var _textBuilt:Boolean = false;
      private function ensureText():void { if (this._textBuilt || stage == null) { return; } this._textBuilt = true; this.buildText(); }

      public function debugRects():Array { return this._panels; }

      // P3: header + list columns switch by sub-tab. AMMO only on Weapons (tab 0); NAME/WT/VAL elsewhere.
      // 0.0.31 UPDATE-ONLY: all header columns sit at FIXED x (set in buildText); switching tabs only TOGGLES
      // AMMO visibility and flips the list's optOn. NO `.x`/`.width`/`.y` write on any text-bearing field, and
      // the column config is never reassigned (crash class (2) needs a geometry write on an interaction path).
      private function layoutHeader():void
      {
         if (this._hdr.length < 4) { return; }
         var weapons:Boolean = (this._curTab == 0);
         this._hdr[1].visible = weapons;                 // AMMO header (visibility toggle only, no geometry write)
         if (this._hdrHit.length > 1 && this._hdrHit[1] != null) { this._hdrHit[1].mouseEnabled = weapons; }   // no dead hit off-weapons
         if (this._list != null) { this._list.optOn = weapons; }
      }

      // 0.0.20 receiver: the DLL pushes worn-armor names to root1.PipOS_equip (10-elem, panel-row order) once
      // on menu-open. We read it off the shared stage root and update the pooled per-slot fields. UPDATE-TEXT-
      // ONLY: no field creation, no .width (the mechanical FindFont rule; ctor_text_check gates this method).
      private var _equipLast:Array = null;    // 0.0.60: last applied names (diff -> pulse changed rows)
      private var _eqPulseLayer:Shape;
      private var _eqPulse:Array = [];        // per-row pulse alpha 0..1
      private function applyEquip():void
      {
         if (this._equipVal == null || this._equipVal.length == 0) { return; }
         try {
            var r:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null;   // == root1 (chrome idiom)
            var eq:* = (r != null) ? r.PipOS_equip : null;
            if (eq == null) { return; }
            var first:Boolean = (this._equipLast == null);
            if (first) { this._equipLast = []; }
            for (var i:int = 0; i < this._equipVal.length; i++) {
               var f:TextField = this._equipVal[i];
               if (f == null) { continue; }
               var nm:String = (i < eq.length && eq[i] != null) ? this.stripTags(String(eq[i])) : "";   // #3: strip FIS tag from equipment slot names
               var shown:String = (nm.length > 0) ? nm : "-";
               // 0.0.60 DIFF-ONLY: setText only when the value actually changed (the DLL re-pushes ~2x/s while
               // the menu is open, so unconditional setText would reformat 10 fields per push for nothing), and
               // flare the row's pulse bar on a real change (skip the very first fill).
               if (this._equipLast[i] != shown) {
                  Theme.setText(f, shown);
                  if (!first) { while (this._eqPulse.length <= i) { this._eqPulse.push(0); } this._eqPulse[i] = 1.0; }
                  this._equipLast[i] = shown;
               }
            }
         } catch (e:*) { }
      }
      // Pulse fade (driven from onCharPoll every frame): redraw the left-edge bars for rows with alpha > 0.
      private function tickEquipPulse(dt:Number):void
      {
         if (this._eqPulseLayer == null) { return; }
         var any:Boolean = false;
         var g:Graphics = this._eqPulseLayer.graphics; g.clear();
         for (var i:int = 0; i < this._eqPulse.length; i++) {
            var a:Number = Number(this._eqPulse[i]);
            if (a <= 0) { continue; }
            a -= dt * 0.9;   // ~1.1s fade
            if (a < 0) { a = 0; }
            this._eqPulse[i] = a;
            if (a > 0) {
               any = true;
               var sy:Number = 30 + i * 30;
               g.beginFill(Theme.PHOS_BRIGHT, a);
               g.drawRect(-8, sy, 3, 24);
               g.endFill();
            }
         }
         if (!any && this._eqPulseAny) { g.clear(); }
         this._eqPulseAny = any;
      }
      private var _eqPulseAny:Boolean = false;

      // POOL BUILDER (called ONCE from buildText, on-stage). Category data changes fire reentrantly inside item
      // clicks (SetQuickkey/SortItemList round-trips), so the strip must NEVER be rebuilt on the change path.
      // Labels are constants; all fields are BOLD so width is FROZEN (active shown by colour + underline, not
      // weight). Measure t.width ONCE here to place the hit rects + advance x, then freeze the underline rects.
      private function buildSubtabs():void
      {
         this._subtabs.graphics.clear();
         var x:Number = Theme.CX;
         this._subFields = []; this._subUL = [];
         for (var i:int = 0; i < CATS.length; i++)
         {
            var t:TextField = Theme.tf(14, Theme.PHOS_DIM, true);   // parity: font 14 + ~24 gap to match DATA + mockup (was 13 / +16)
            this._subtabs.addChild(t); t.name = "c" + i; t.x = x; t.y = 0; Theme.setText(t, CATS[i]);
            this._subFields.push(t);
            var hit:Sprite = new Sprite();
            hit.graphics.beginFill(0, 0.004); hit.graphics.drawRect(x - 4, -2, t.width + 8, 22); hit.graphics.endFill();
            hit.name = "h" + i; hit.buttonMode = true; hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onSubtabClick);
            hit.addEventListener(MouseEvent.ROLL_OVER, this.onSubtabOver); hit.addEventListener(MouseEvent.ROLL_OUT, this.onSubtabOut);   // 0.0.59 hover
            this._subtabs.addChild(hit);
            this._subUL.push({ x:(x - 4), w:(t.width + 8) });
            x += t.width + 24;
         }
         this.updateSubtabs();
      }
      // 0.0.59 HOVER (parity with Stats/Data): recolour-only, crash-law-safe.
      private function onSubtabOver(e:MouseEvent):void
      {
         var i:int = int(e.currentTarget.name.substr(1));
         if (i != this._curTab && i < this._subFields.length) { (this._subFields[i] as TextField).textColor = Theme.PHOS_BRIGHT; }
      }
      private function onSubtabOut(e:MouseEvent):void
      {
         var i:int = int(e.currentTarget.name.substr(1));
         if (i != this._curTab && i < this._subFields.length) { (this._subFields[i] as TextField).textColor = Theme.PHOS_DIM; }
      }
      // UPDATE-ONLY (tab change): recolour the frozen labels + redraw the underline from stored rects.
      private function updateSubtabs():void
      {
         this._subtabs.graphics.clear();
         for (var i:int = 0; i < this._subFields.length; i++)
         {
            var on:Boolean = (i == this._curTab);
            (this._subFields[i] as TextField).textColor = on ? Theme.PHOS_BRIGHT : Theme.PHOS_DIM;
            // Parity fix C3: active sub-tab marked by the mockup's three-dot ". . ." indicator (font-independent
            // vector dots on this pooled layer), not the old solid underline bar.
            if (on && i < this._subUL.length) {
               var cx:Number = this._subUL[i].x + this._subUL[i].w / 2; var dy:Number = 22; var dr:Number = 1.4; var gap:Number = 7;
               this._subtabs.graphics.beginFill(Theme.SEL, 0.95);
               this._subtabs.graphics.drawCircle(cx - gap, dy, dr); this._subtabs.graphics.drawCircle(cx, dy, dr); this._subtabs.graphics.drawCircle(cx + gap, dy, dr);
               this._subtabs.graphics.endFill();
            }
         }
      }
      // P1-A: route sub-tab clicks through the shell's guarded TryToSetTab(uint) (the path keyboard/engine
      // uses: CanSwitchTabs then onNewTab), acquired the same way Chrome does. The direct onNewTab is kept
      // ONLY as a fallback when the menu ref can't be acquired. Menu ref cached after first success.
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
         if (this._dbg != null) this._dbg.input("subtab", i, e.currentTarget);   // P3/W5c
         if (i == this._curTab) { return; }
         this.sfx("UIMenuPrevNext");
         var m:Object = this.acquireMenu();
         var routed:Boolean = false;
         if (m != null) { try { m.TryToSetTab(i); routed = true; } catch (er:*) { routed = false; } }
         if (!routed) { BGSExternalInterface.call(this.codeObj, "onNewTab", i); }
      }

      override protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void
      {
         super.onPipboyChangeEvent(param1);
         this.ensureText(); if (!this._textBuilt) { return; }
         var d:Pipboy_DataObj = param1.DataObj; this._lastData = d;
         if (this._dbg != null) { this._dbg.change(); this._dbg.pageTab(d.CurrentPage, d.CurrentTab); }
         this._curTab = d.CurrentTab; this.updateSubtabs(); this.layoutHeader(); this.applyEquip();

         // 0.0.31: WEIGHT/CAPS are FIXED-position autoSize="none" right-aligned boxes (geometry baked once in
         // buildText). The refresh path is UPDATE-ONLY: setText + textColor only -- no position/size writes (the
         // former right-edge reflow, which read a field width then moved it on the change path, was a geometry
         // write on a text-bearing field == crash class (2)). Icons redraw at the fixed box-left x (reads only).
         Theme.setText(this._weight, "WEIGHT " + Math.round(d.CurrWeight) + "/" + Math.round(d.MaxWeight));
         var over:Boolean = (d.MaxWeight > 0 && d.CurrWeight >= d.MaxWeight);
         this._weight.textColor = over ? Theme.CRIT : (d.MaxWeight > 0 && d.CurrWeight >= d.MaxWeight * 0.9 ? Theme.WARN : Theme.PHOS_BRIGHT);
         Theme.setText(this._caps, "CAPS " + d.Caps);
         this._wIcon.graphics.clear();
         Theme.iconWeight(this._wIcon.graphics, this._weight.x - 16, Theme.SUB_Y + 4, 13, this._weight.textColor);
         Theme.iconCaps(this._wIcon.graphics, this._caps.x - 16, Theme.SUB_Y + 4, 13, Theme.PHOS_BRIGHT);

         // P1-D: pick up the DLL's per-item WT/VAL/AMMO map (name -> {w,v,a}) BEFORE the sort/adapter reads it.
         // TASK B (0.0.33): also cache the item-card data maps (stats + installed-mods, keyed by decimal formID
         // string) so renderCard can join on the selected row's formID. Absent members degrade to blank fields.
         this._itemInfo = null; this._itemStats = null; this._itemMods = null; this._favs = null;
         // 0.0.38: refresh the folders toggle from the DLL push (fallback to Theme.FOLDERS => 0.0.37 behavior).
         // 0.0.43: refresh the RPM display switch from the same push (fallback FALSE => firerate behavior).
         this._foldersOn = Theme.FOLDERS; this._showRPM = false;
         try { var rr:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null; if (rr != null) { this._itemInfo = rr.PipOS_iteminfo; this._itemStats = rr.PipOS_itemstats; this._itemMods = rr.PipOS_itemmods; this._favs = rr.PipOS_favorites; var st:* = rr.PipOS_settings; if (st != null && st.hasOwnProperty("folders")) { this._foldersOn = (st.folders == true); } if (st != null && st.hasOwnProperty("showRPM")) { this._showRPM = (st.showRPM == true); } this.hydrateFolderMem(rr); this.hydrateListMem(rr); } } catch (ex:*) { this._itemInfo = null; this._itemStats = null; this._itemMods = null; this._favs = null; }
         // The native favorite mirror supplies stable form IDs/counts; the engine DataObj supplies vanilla's
         // icon-frame contract. Merge by quick-key slot before renderQuick without replacing either source.
         if (this._favs != null && d.FavoritesList != null) {
            for (var fi:int = 0; fi < this._favs.length && fi < d.FavoritesList.length; fi++) {
               if (this._favs[fi] != null && d.FavoritesList[fi] != null && d.FavoritesList[fi].FavIconType != null) {
                  this._favs[fi].FavIconType = d.FavoritesList[fi].FavIconType;
               }
            }
         }
         this.hideTooltip();   // B: drop any stale tooltip across a data refresh (re-shown on next hover)
         this.closeContextMenu();   // 0.0.61: a live data refresh rebuilds the list -> drop any open context menu
         // Filter (vanilla ListFilterer rule) + per-category sort + setItems, preserving the selected item.
         this.rebuildList(d);
         this.updateInvTitle(); this.drawSortIndicator();
         if (this._vb != null) { try { this._vb.setFlags(d.BodyFlags, d.HeadFlags); } catch (ev:Error) {} }
         SetIsDirty();
      }

      private function invIdx(listIdx:int):int { return (listIdx >= 0 && listIdx < this._invMap.length) ? int(this._invMap[listIdx]) : listIdx; }

      private function itemAdapter(e:Object):Object
      {
         if (e == null) { return { cols:["","","",""], star:false, legendary:false, dim:false }; }
         // FIS FOLDER header row: a page-injected marker (see groupPairs). Rendered as a CLICKABLE separator by
         // PipList (caret + "TAG (n)"); carries no formID/join so _invMap holds -1 for it. Never an item.
         if (e.__folder == true) { return { separator:true, folder:true, collapsed:(e.collapsed == true), label:String(e.label != null ? e.label : e.tag), count:int(e.count) }; }
         // JOIN KEY stays the RAW in-game name (e.text): the DLL keys PipOS_iteminfo/itemstats/itemmods off the
         // tagged name the engine reports, so we join on `bare` (unchanged) but DISPLAY the tag-stripped clean name.
         var bare:String = (e.text != null ? String(e.text) : "");
         var disp:String = this.parseTag(bare).clean; if (disp == null || disp.length == 0) { disp = bare; }
         var nm:String = disp + ((e.count != null && e.count != 1) ? " (" + e.count + ")" : "");
         // P1-D: pull WT/VAL/AMMO from the DLL-pushed map keyed by the bare display name (== the row .text).
         var w:String = "", v:String = "", a:String = "";
         if (this._itemInfo != null) {
            var info:Object = null;
            try { info = this._itemInfo[bare]; } catch (er:*) { info = null; }
            if (info != null) {
               if (info.w != null) { w = String(info.w); }
               if (info.v != null) { v = String(info.v); }
               if (info.a != null) { a = this.stripTags(String(info.a)); }   // #3: strip FIS tag from the AMMO cell
            }
         }
         // Always 4 cols aligned to the stable pool (NAME|AMMO|WT|VAL); AMMO stays "" off-weapons and PipList
         // hides it via optOn, widening the NAME viewport by scrollRect only (no geometry write on tab change).
         var cols:Array = [nm, a, w, v];
         // P2-C: star == favorite, EXACTLY as vanilla InvListEntry (param1.favorite > 0). legendary mirrors
         // vanilla LegendaryIcon (param1.isLegendary). Both are the ground-truth vanilla rules, not guesses.
         // 0.0.63: equipped indicator -- InvItems rows carry equipState (0 = not equipped; the backtick dump
         // confirmed it). Non-zero => currently worn/wielded; PipList draws a bright left-edge accent bar.
         var eqp:Boolean = (e.equipState != null && int(e.equipState) != 0);
         return { cols: cols, star:(e.favorite > 0), legendary:(e.isLegendary == true), equipped:eqp, dim:false };
      }
      // 0.0.63: canonical unsigned formID key. The ENGINE hands AS the formID as a SIGNED 32-bit int (a mod/ESL
      // form with the high bit set reads NEGATIVE, e.g. Desert Warrior -32675651), but the DLL keys itemstats/
      // itemmods with "%u" (unsigned, 4262291645). String(formID) therefore never matched for high-bit forms ->
      // those weapons showed no DMG/RPM/ammo. uint() wraps the signed value to the same unsigned decimal.
      private function fidKey(formID:*):String
      {
         var n:Number = Number(formID);
         if (isNaN(n)) { return String(formID); }
         return String(uint(n));
      }

      // ==========================================================================================
      // FIS / Complex Sorter / FallUI TAG PARSER + FOLDER GROUPING (pure derivation; no TextField access).
      //
      // parseTag(raw) -> { tag:String|null, clean:String }. Rules (deliberately conservative):
      //   1. Strip ALL Private-Use-Area icon glyphs (U+E000..U+F8FF) anywhere -- FallUI's sorter fonts map these
      //      to category icons we do NOT ship, so they render as tofu; they never survive into the display label.
      //   2. Only a LEADING bracket token counts as a tag: [..], {..} or (..). Up to a few STACKED leading tokens
      //      are stripped from the clean name (FIS emits e.g. "[Weapon][Auto]Name"); the FIRST plausible token is
      //      the GROUP tag. A '|' sub-tag ("[Aid|Food]") groups by the part before the bar ("Aid").
      //   3. A token is only accepted if it is a PLAUSIBLE tag (<=24 chars, tag-ish chars only, >=1 letter) so a
      //      real item name that merely CONTAINS parentheses mid-string (or opens with a numeric "(2)") is left
      //      untouched -- no false grouping. If nothing qualifies, tag=null (the item is ungrouped).
      private function parseTag(raw:String):Object
      {
         if (raw == null) { return { tag:null, clean:"" }; }
         var s:String = this.ltrim(this.stripPUA(String(raw)));
         var firstTag:String = null;
         var guard:int = 0;
         while (guard < 4 && s.length > 0) {
            guard++;
            var open:String = s.charAt(0);
            var close:String = (open == "[") ? "]" : ((open == "{") ? "}" : ((open == "(") ? ")" : ""));
            if (close == "") { break; }
            var end:int = s.indexOf(close, 1);
            if (end < 1) { break; }
            var inner:String = s.substring(1, end);
            if (!this.isPlausibleTag(inner)) { break; }
            if (firstTag == null) {
               var primary:String = inner; var bar:int = inner.indexOf("|");
               if (bar >= 0) { primary = inner.substring(0, bar); }
               primary = this.trimStr(primary);
               if (primary.length > 0) { firstTag = primary; }
            }
            s = this.ltrim(s.substring(end + 1));
         }
         return { tag: firstTag, clean: s };
      }
      private function stripPUA(s:String):String
      {
         if (s == null) { return ""; }
         var out:String = ""; var hadPUA:Boolean = false;
         for (var i:int = 0; i < s.length; i++) {
            var c:int = s.charCodeAt(i);
            if (c >= 0xE000 && c <= 0xF8FF) { hadPUA = true; continue; }
            out += s.charAt(i);
         }
         return hadPUA ? this.trimStr(out) : out;
      }
      private function isPlausibleTag(inner:String):Boolean
      {
         if (inner == null) { return false; }
         var n:int = inner.length;
         if (n == 0 || n > 24) { return false; }
         var hasAlpha:Boolean = false;
         for (var i:int = 0; i < n; i++) {
            var c:int = inner.charCodeAt(i);
            var isL:Boolean = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
            var isD:Boolean = (c >= 48 && c <= 57);
            // tag-ish punctuation only: space | & - . , ' /
            var ok:Boolean = isL || isD || c == 32 || c == 124 || c == 38 || c == 45 || c == 46 || c == 44 || c == 39 || c == 47;
            if (!ok) { return false; }
            if (isL) { hasAlpha = true; }
         }
         return hasAlpha;
      }
      private function ltrim(s:String):String { var i:int = 0; while (i < s.length && s.charCodeAt(i) == 32) { i++; } return s.substr(i); }
      private function trimStr(s:String):String { var a:int = 0, b:int = s.length; while (a < b && s.charCodeAt(a) == 32) { a++; } while (b > a && s.charCodeAt(b - 1) == 32) { b--; } return s.substring(a, b); }

      // #3 (0.0.42) TAG STRIP for ANY DISPLAYED item text (card title/sub/ammo, list AMMO cell, equipment names,
      // tooltip caliber). Reuses the parseTag rules (strip leading [..]/{..}/(..) tokens + PUA icon glyphs). Join
      // keys elsewhere stay RAW; this is display-only. Falls back to the raw string if stripping empties it.
      private function stripTags(raw:String):String
      {
         if (raw == null) { return ""; }
         var c:String = this.parseTag(raw).clean;
         return (c != null && c.length > 0) ? c : String(raw);
      }

      // ==========================================================================================
      // #4 (0.0.42) FOLDER CATEGORY MAP + HUMANIZE. FIS/Complex-Sorter emit one raw token per micro-type
      // ("[AssaultRifle]", "[TireIron]", "[Ranged]", "[Eyes]"), which produced a folder-per-token wall of
      // code-name headers. We instead map each raw tag to a small, sensible bucket and show a humanized label:
      //   WEAPONS tab (0): keyword classification collapses micro-types into families --
      //     *RIFLE|MUSKET|CARBINE|SNIPER|LEVERACTION      -> RIFLE     ("RIFLES")
      //     *PISTOL|REVOLVER|HANDGUN|MAGNUM|DELIVERER|10MM -> PISTOL    ("PISTOLS")
      //     *SHOTGUN                                       -> SHOTGUN   ("SHOTGUNS")
      //     *SMG|SUBMACHINE                                -> SMG       ("SMGS")
      //     *MINIGUN|MISSILE|FATMAN|GATLING|FLAMER|LAUNCHER|CANNON|GAUSS|HEAVY -> HEAVY ("HEAVY WEAPONS")
      //     *LASER|PLASMA|GAMMA|INSTITUTE|CRYO|ENERGY      -> ENERGY    ("ENERGY WEAPONS")
      //     *MOLOTOV|GRENADE|MINE|FRAG|BOMB|THROW|NUKA     -> THROWN    ("THROWN")
      //     known melee names (TireIron, Knife, Machete, Bat, ... ) -> MELEE ("MELEE")
      //     everything else -- generic supertypes (RANGED) and one-off oddities (EYES) -> MISC ("MISC")
      //   OTHER tabs: pass the raw tag through as its own bucket, humanized (apparel slots like "LeftArm" ->
      //   "LEFT ARM" read fine as-is; no forced merge).
      // The bucket KEY is the collapse-memory + ordering key (stable across refreshes); the LABEL is display-only.
      private function folderBucket(rawTag:String, tab:int):String
      {
         var u:String = rawTag.toUpperCase();
         var k:String = u.split(" ").join("").split("-").join("").split("_").join("");   // de-spaced for keyword match
         if (tab == 0) {
            if (this.hasSub(k, "SHOTGUN")) { return "SHOTGUN"; }
            if (this.hasAny(k, ["RIFLE", "MUSKET", "CARBINE", "SNIPER", "LEVERACTION"])) { return "RIFLE"; }
            if (this.hasAny(k, ["PISTOL", "REVOLVER", "HANDGUN", "MAGNUM", "DELIVERER", "10MM", "44"])) { return "PISTOL"; }
            if (this.hasAny(k, ["SMG", "SUBMACHINE"])) { return "SMG"; }
            if (this.hasAny(k, ["MINIGUN", "MISSILE", "FATMAN", "GATLING", "FLAMER", "LAUNCHER", "CANNON", "GAUSS", "HEAVY"])) { return "HEAVY"; }
            if (this.hasAny(k, ["LASER", "PLASMA", "GAMMA", "INSTITUTE", "CRYO", "ENERGY"])) { return "ENERGY"; }
            if (this.hasAny(k, ["MOLOTOV", "GRENADE", "MINE", "FRAG", "BOMB", "THROW", "NUKA"])) { return "THROWN"; }
            if (this.isMeleeTag(k)) { return "MELEE"; }
            // WEAPONS-tab fallback: an item that matched no ranged/energy/thrown FAMILY is almost always a MELEE
            // weapon (tire irons, boards, unique melee whose FIS tag we don't recognize by name). Route those to
            // MELEE, not MISC (user: "the tire iron is a melee weapon so it should be under Melee"). Reserve MISC
            // only for an explicitly GENERIC ranged supertype tag ("[Ranged]"/"[Gun]") that names no real family.
            if (this.hasAny(k, ["RANGED", "GUN", "FIREARM"])) { return "MISC"; }
            return "MELEE";
         }
         return u;   // non-weapon tabs: raw tag == its own bucket
      }
      private function isMeleeTag(k:String):Boolean
      {
         // NOTE: family checks (RIFLE/PISTOL/SHOTGUN/...) run BEFORE this, so substrings like "BAT" inside
         // "COMBATRIFLE" never reach here. Keywords kept specific ("BASEBALL" not "BAT") to avoid false positives.
         return this.hasAny(k, ["MELEE", "TIREIRON", "KNIFE", "MACHETE", "SWORD", "BLADE", "KNUCKLE", "WRENCH",
            "HAMMER", "AXE", "RIPPER", "SLEDGE", "WALKINGCANE", "POOLCUE", "BASEBALL", "BOARD", "GAUNTLET",
            "PIPEWRENCH", "SHISHKEBAB", "ROLLINGPIN", "CROWBAR", "BOXING", "SWITCHBLADE"]);
      }
      private function hasSub(hay:String, needle:String):Boolean { return hay.indexOf(needle) >= 0; }
      private function hasAny(hay:String, needles:Array):Boolean
      {
         for (var i:int = 0; i < needles.length; i++) { if (hay.indexOf(String(needles[i])) >= 0) { return true; } }
         return false;
      }
      // Display label for a bucket. Weapon families use a fixed readable/pluralized name; every other bucket
      // (non-weapon tabs) is humanized from a SAMPLE original-case tag (camel/joined split -> spaced -> CAPS).
      private function folderLabel(bucketKey:String, sampleOrig:String, tab:int):String
      {
         if (tab == 0) {
            switch (bucketKey) {
               case "PISTOL":  return "PISTOLS";
               case "RIFLE":   return "RIFLES";
               case "SHOTGUN": return "SHOTGUNS";
               case "SMG":     return "SMGS";
               case "HEAVY":   return "HEAVY WEAPONS";
               case "ENERGY":  return "ENERGY WEAPONS";
               case "THROWN":  return "THROWN";
               case "MELEE":   return "MELEE";
               case "MISC":    return "MISC";
            }
         }
         return this.humanize(sampleOrig);
      }
      // Split camelCase / joined-word / letter<->digit boundaries into spaces, collapse separators, UPPERCASE
      // (the mockup's folder/section treatment is all-caps). Pure char scan; no TextField access.
      private function humanize(s:String):String
      {
         if (s == null || s.length == 0) { return ""; }
         var out:String = ""; var n:int = s.length;
         for (var i:int = 0; i < n; i++) {
            var c:int = s.charCodeAt(i);
            if (c == 45 || c == 95 || c == 47) { out += " "; continue; }   // - _ / -> space
            if (i > 0) {
               var p:int = s.charCodeAt(i - 1);
               var pLower:Boolean = (p >= 97 && p <= 122); var pUpper:Boolean = (p >= 65 && p <= 90);
               var pDigit:Boolean = (p >= 48 && p <= 57); var cUpper:Boolean = (c >= 65 && c <= 90);
               var cDigit:Boolean = (c >= 48 && c <= 57); var cLetter:Boolean = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
               // boundaries: lower|digit -> Upper ; letter -> digit ; digit -> letter
               if (((pLower || pDigit) && cUpper) || ((pUpper || pLower) && cDigit) || (pDigit && cLetter)) { out += " "; }
            }
            out += s.charAt(i);
         }
         // collapse doubled spaces + trim, then uppercase
         var collapsed:String = ""; var prevSp:Boolean = false;
         for (var j:int = 0; j < out.length; j++) { var ch:String = out.charAt(j); if (ch == " ") { if (!prevSp) { collapsed += ch; } prevSp = true; } else { collapsed += ch; prevSp = false; } }
         return this.trimStr(collapsed).toUpperCase();
      }

      // Group the (already sorted) filtered {it,oi} pairs under folder headers. Returns {entries, map, grouped}.
      // Zero behaviour change when Theme.FOLDERS is off OR no item carries a tag: the flat item list is returned
      // exactly as before. When grouped, folders are ordered alphabetically with the untagged "MISC" folder last;
      // items keep their incoming (sorted) order within each folder; collapsed folders omit their child rows.
      private function groupPairs(pairs:Array):Object
      {
         var entries:Array = []; var map:Array = []; var i:int;
         var tab:int = this._curTab;
         // Per-pair canonical bucket KEY (collapse-memory/order key) + a sample original-case tag (for the label).
         var keys:Array = []; var anyTag:Boolean = false;
         var labelOf:Object = {};   // bucketKey -> display label (first sample wins; weapon buckets are fixed)
         if (this._foldersOn) {
            for (i = 0; i < pairs.length; i++) {
               var pt:Object = this.parseTag(this.itemName(pairs[i].it));
               var orig:String = (pt.tag != null) ? String(pt.tag) : null;
               var bkey:String = (orig != null) ? this.folderBucket(orig, tab) : null;
               keys.push(bkey);
               if (bkey != null) { anyTag = true; if (labelOf[bkey] == null) { labelOf[bkey] = this.folderLabel(bkey, orig, tab); } }
            }
         }
         if (!anyTag) {
            this._curFolderKeys = [];   // 0.0.61: flat list (no folders) -> nothing for Expand/Collapse All
            for (i = 0; i < pairs.length; i++) { entries.push(pairs[i].it); map.push(int(pairs[i].oi)); }
            return { entries:entries, map:map, grouped:false };
         }
         var UNTAG:String = "MISC";
         if (labelOf[UNTAG] == null) { labelOf[UNTAG] = "MISC"; }
         var order:Array = []; var buckets:Object = {};
         for (i = 0; i < pairs.length; i++) {
            var key:String = (keys[i] != null) ? String(keys[i]) : UNTAG;
            if (buckets[key] == null) { buckets[key] = []; order.push(key); }
            (buckets[key] as Array).push(i);
         }
         order.sort();
         var ui:int = order.indexOf(UNTAG);
         if (ui >= 0) { order.splice(ui, 1); order.push(UNTAG); }   // catch-all MISC folder always trails
         this._curFolderKeys = order.concat();   // 0.0.61: stash this tab's folder keys for Expand All / Collapse All
         for (var gi:int = 0; gi < order.length; gi++) {
            var k:String = String(order[gi]); var idxs:Array = buckets[k] as Array;
            var lbl:String = (labelOf[k] != null) ? String(labelOf[k]) : k;
            var collapsed:Boolean = this.isFolderCollapsed(tab, k);
            entries.push({ __folder:true, tag:k, label:lbl, count:idxs.length, collapsed:collapsed }); map.push(-1);
            if (!collapsed) {
               for (var j:int = 0; j < idxs.length; j++) { var p:Object = pairs[int(idxs[j])]; entries.push(p.it); map.push(int(p.oi)); }
            }
         }
         return { entries:entries, map:map, grouped:true };
      }

      // #6 (0.0.42): folders are COLLAPSED BY DEFAULT. _folderState now records the OPENED folders (presence == open,
      // absence == collapsed) -- the inverse of the old memory -- so an untouched folder renders collapsed and the
      // user's opened folders are remembered across refreshes/re-sorts/tab-switches within the session. (_folderState
      // lives on the page, so it survives every in-session rebuild; cross-SESSION persistence would need a DLL/disk
      // store we don't have from AS3 -- SharedObject is unreliable under Scaleform GFx -- so it resets on menu reopen.)
      private function isFolderCollapsed(tab:int, key:String):Boolean
      {
         if (tab < 0 || tab >= this._folderState.length) { return true; }   // default collapsed
         var m:Object = this._folderState[tab];
         return !(m != null && m[key] == true);   // opened iff explicitly recorded; else collapsed
      }
      private function setFolderCollapsed(tab:int, key:String, collapsed:Boolean):void
      {
         if (tab < 0 || tab >= this._folderState.length) { return; }
         if (this._folderState[tab] == null) { this._folderState[tab] = {}; }
         if (collapsed) { delete this._folderState[tab][key]; } else { this._folderState[tab][key] = true; }
         this.persistFolderMem();   // 0.0.59: mirror every change out to the DLL-backed session store
      }
      // 0.0.59 SESSION FOLDER MEMORY: the page dies with the menu, so opened-folder state is mirrored into
      // root1.PipOS_folderMem (string "tab:KEY|KEY;tab:KEY"). The DLL reads it at menu close and re-seeds it on
      // the next open (survives across Pip-Boy opens within a game session; intentionally not saved to disk).
      private var _folderMemLoaded:Boolean = false;
      private function persistFolderMem():void
      {
         try {
            var rr:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null;
            if (rr == null) { return; }
            var s:String = "";
            for (var t:int = 0; t < this._folderState.length; t++) {
               var m:Object = this._folderState[t]; if (m == null) { continue; }
               var keys:String = "";
               for (var k:String in m) { if (m[k] == true) { keys += (keys.length > 0 ? "|" : "") + k; } }
               if (keys.length > 0) { s += (s.length > 0 ? ";" : "") + t + ":" + keys; }
            }
            rr.PipOS_folderMem = s;
         } catch (ep:*) {}
      }
      private function hydrateFolderMem(rr:*):void
      {
         if (this._folderMemLoaded) { return; }
         this._folderMemLoaded = true;
         try {
            var s:* = (rr != null) ? rr.PipOS_folderMem : null;
            if (s == null) { return; }
            var tabs:Array = String(s).split(";");
            for (var i:int = 0; i < tabs.length; i++) {
               var part:String = String(tabs[i]); var c:int = part.indexOf(":"); if (c <= 0) { continue; }
               var t:int = int(part.substr(0, c));
               if (t < 0 || t >= this._folderState.length) { continue; }
               if (this._folderState[t] == null) { this._folderState[t] = {}; }
               var keys:Array = part.substr(c + 1).split("|");
               for (var j:int = 0; j < keys.length; j++) { var k:String = String(keys[j]); if (k.length > 0) { this._folderState[t][k] = true; } }
            }
         } catch (eh:*) {}
      }

      // Session list-position memory, mirrored through root1 and banked by the DLL on menu close. Format is
      // "tab,selectedDisplayIndex,topDisplayIndex;...". Selection + top are stored per inventory category.
      private function persistListMem():void
      {
         if (this._list != null && this._builtTab >= 0 && this._builtTab < this._listSelMem.length) {
            this._listSelMem[this._builtTab] = this._list.selectedIndex;
            this._listTopMem[this._builtTab] = this._list.topIndex;
         }
         try {
            var rr:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null; if (rr == null) { return; }
            var s:String = "";
            for (var t:int = 0; t < this._listSelMem.length; t++) {
               s += (s.length > 0 ? ";" : "") + t + "," + int(this._listSelMem[t]) + "," + int(this._listTopMem[t]);
            }
            rr.PipOS_invListMem = s;
         } catch (ep:*) {}
      }
      private function hydrateListMem(rr:*):void
      {
         if (this._listMemLoaded) { return; } this._listMemLoaded = true;
         try {
            var raw:* = (rr != null) ? rr.PipOS_invListMem : null; if (raw == null) { return; }
            var parts:Array = String(raw).split(";");
            for (var i:int = 0; i < parts.length; i++) {
               var v:Array = String(parts[i]).split(","); if (v.length < 3) { continue; }
               var t:int = int(v[0]); if (t < 0 || t >= this._listSelMem.length) { continue; }
               this._listSelMem[t] = int(v[1]); this._listTopMem[t] = int(v[2]);
            }
         } catch (eh:*) {}
      }
      private function onListViewport(sel:int, top:int):void { this.persistListMem(); }
      // Folder header click (from PipList.onFolderToggle): flip this category+tag's collapse state and rebuild.
      // Pool-safe: rebuildList -> setItems/selectIndexSilent are update-only on the already-built pool.
      private function onFolderToggle(entry:Object):void
      {
         if (entry == null || entry.tag == null) { return; }
         var tab:int = this._curTab; var key:String = String(entry.tag);
         this.setFolderCollapsed(tab, key, !this.isFolderCollapsed(tab, key));
         this.sfx("UIMenuPrevNext");
         if (this._lastData != null) { this.rebuildList(this._lastData); this.updateInvTitle(); this.drawSortIndicator(); }
      }

      private function onListSel(i:int):void
      {
         this.persistListMem();
         this._dmgIndex = 0; var oi:int = this.invIdx(i);
         // TASK B: remember the selected InvItems row so renderCard can join it against the DLL data maps.
         this._selRow = (this._lastData != null && this._lastData.InvItems != null && oi >= 0 && oi < this._lastData.InvItems.length) ? this._lastData.InvItems[oi] : null;
         BGSExternalInterface.call(this.codeObj, "onInvItemSelection", oi, this._cardInfo, this._paperInfo, this);
         // P0 (0.0.27): the item card never populated because renderCard() was ONLY reachable from the vanilla
         // BSScrollingList hook onListSelectionChangeCallback -- but we drive selection through our own PipList,
         // which never fires it. onInvItemSelection fills _cardInfo SYNCHRONOUSLY (by reference) before it
         // returns, so render the card directly here. (onListSelectionChangeCallback -> renderCard is kept too,
         // harmless if the engine also calls it.) renderCard is update-only (setText + the safe .x-by-width-read).
         this.renderCard();
         BGSExternalInterface.call(this.codeObj, "updateItem3D", oi);
      }
      private function onListPress(i:int):void { BGSExternalInterface.call(this.codeObj, "SelectItem", this.invIdx(i)); }
      public function onListSelectionChangeCallback():*
      {
         this.renderCard();
         dispatchEvent(new flash.events.Event(PipboyPage.BOTTOM_BAR_UPDATE, true, true));
         SetIsDirty();
      }
      public function onSortComplete(param1:int):* { this.sfx("UIMenuPrevNext"); }

      // TASK B: fill the item card from the DLL push. UPDATE-ONLY -- every field's geometry is baked in buildText;
      // here we only redraw graphics (chip boxes/icons, diamonds, legendary sparkle) and set .text/.textColor/
      // .visible. The join key is the selected row's decimal formID string against PipOS_itemstats/itemmods; the
      // WT/CAPS chips come from PipOS_iteminfo (by bare name). Missing numeric fields show an em-dash; the card
      // never blanks wholesale on a partial/absent push (er/rr are frequently omitted -- handled per field).
      private function renderCard():void
      {
         if (this._cardTitle == null) { return; }
         var g:* = this._card.graphics; g.clear();
         var CWID:Number = this.LW - 2 * Theme.PAD;
         var DASH:String = "—";

         var row:Object = this._selRow;
         // Parity empty state (mockup): no selected row / empty category -> em-dash name + a neutral flavor line,
         // never a blank card. Update-only (setText/visible; graphics already cleared above).
         if (row == null) {
            Theme.setText(this._cardTitle, DASH);
            this._cardSub.visible = false; this._cardDmg.visible = false;
            this._cardWt.visible = false; this._cardCaps.visible = false; this._cardLeg.visible = false;
            for (var pz:int = 0; pz < 6; pz++) { this._cardPairL[pz].visible = false; this._cardPairV[pz].visible = false; }
            this._cardDesc.visible = true; Theme.setText(this._cardDesc, "Nothing in this category.");
            return;
         }
         var stats:Object = null; var mods:Array = null;
         if (row != null && row.formID != null && this._itemStats != null) {
            try { stats = this._itemStats[this.fidKey(row.formID)]; } catch (e1:*) { stats = null; }
         }
         if (row != null && row.formID != null && this._itemMods != null) {
            try { mods = this._itemMods[this.fidKey(row.formID)] as Array; } catch (e2:*) { mods = null; }
         }
         var type:String = (stats != null && stats.type != null) ? String(stats.type) : "";

         // TITLE (uppercase, markers stripped) + top-right SUB (caliber/type + LEGENDARY/EQUIPPED).
         Theme.setText(this._cardTitle, this.cardName(row));
         Theme.setText(this._cardSub, this.cardSubStr(row, stats, type)); this._cardSub.visible = true;
         this._cardDmg.visible = false;   // parked legacy field

         // WT / CAPS chips (values from PipOS_iteminfo by bare display name; em-dash on miss). Boxes/icons = graphics.
         var bare:String = (row != null && row.text != null) ? String(row.text) : "";
         var wStr:String = DASH, vStr:String = DASH;
         if (this._itemInfo != null && bare.length > 0) {
            var info:Object = null; try { info = this._itemInfo[bare]; } catch (e3:*) { info = null; }
            if (info != null) { if (info.w != null) { wStr = String(info.w); } if (info.v != null) { vStr = String(info.v); } }
         }
         Theme.frameRect(g, 0, 24, 74, 20, Theme.LINE, 0.4); Theme.frameRect(g, 84, 24, 74, 20, Theme.LINE, 0.4);   // 0.0.60: compacted bands
         Theme.iconWeight(g, 8, 27, 13, Theme.PHOS); Theme.iconCaps(g, 92, 27, 13, Theme.PHOS);
         Theme.setText(this._cardWt, wStr); this._cardWt.visible = true;
         Theme.setText(this._cardCaps, vStr); this._cardCaps.visible = true;

         // LEGENDARY line (only when the row is legendary). Sparkle drawn in graphics; text = effect or generic.
         var isLeg:Boolean = (row != null && row.isLegendary == true);
         if (isLeg) { Theme.legendaryMark(g, 6, 52, 5, Theme.WARN); Theme.setText(this._cardLeg, this.cardLegStr(stats, mods)); this._cardLeg.visible = true; }   // 0.0.60: matching diamond on the card (compacted y)
         else { this._cardLeg.visible = false; }

         // STAT PAIRS (up to 4, per category). UPDATE-ONLY: fixed slots; only .text/.visible/.textColor + diamonds.
         var pairs:Array = this.cardPairsFor(row, stats, type);
         var gy:Number = 64;   // 0.0.60: must match CARD_GY in buildText
         for (var p:int = 0; p < 6; p++) {
            if (p < 4 && p < pairs.length) {
               var colX:Number = (p % 2 == 0) ? 0 : CWID / 2; var rowY:Number = gy + Math.floor(p / 2) * 15;
               Theme.diamond(g, colX + 3, rowY + 8, 3, Theme.PHOS_DIM);
               var lt:TextField = this._cardPairL[p]; lt.visible = true; Theme.setText(lt, String(pairs[p].t));
               var vv:String = String(pairs[p].v);
               var vt:TextField = this._cardPairV[p]; vt.visible = true; Theme.setText(vt, vv);
               // 0.0.62: color-code the apparel comparison -- green when this item is BETTER in that stat than
               // what's equipped, red when worse; otherwise the normal bright value (dim for the no-data dash).
               var dd:int = (pairs[p].d != null) ? int(pairs[p].d) : 0;
               vt.textColor = (vv == DASH) ? Theme.PHOS_DIM : ((dd > 0) ? 0x7CFC5A : ((dd < 0) ? Theme.CRIT : Theme.PHOS_BRIGHT));
            } else { this._cardPairL[p].visible = false; this._cardPairV[p].visible = false; }
         }

         // 0.0.60: flavor band retired (space went to the 15th list row); the derived line lives in the hover
         // tooltip instead. Field stays pooled + permanently hidden.
         this._cardDesc.visible = false;
      }

      // ---- TASK B pure derivation helpers (no TextField access; gated update-only by ctor_text_check) ----
      private function selRow():Object
      {
         if (this._list == null || this._lastData == null || this._lastData.InvItems == null) { return null; }
         var oi:int = this.invIdx(this._list.selectedIndex);
         return (oi >= 0 && oi < this._lastData.InvItems.length) ? this._lastData.InvItems[oi] : null;
      }
      private function stripMarkers(s:String):String
      {
         if (s == null) { return ""; }
         var out:String = s;
         // row.text is already the bare name; defensively trim any leading non-alphanumeric marker chars/space.
         while (out.length > 0) { var c0:int = out.charCodeAt(0); if ((c0 >= 48 && c0 <= 57) || (c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122)) { break; } out = out.substr(1); }
         var i:int = out.length; while (i > 0 && out.charCodeAt(i - 1) == 32) { i--; } return out.substr(0, i);
      }
      private function cardName(row:Object):String
      {
         var nm:String = "";
         if (row != null && row.text != null) { nm = String(row.text); }
         else if (this._cardInfo != null && this._cardInfo.length > 0 && this._cardInfo[0] != null && this._cardInfo[0].text != null) { nm = String(this._cardInfo[0].text); }
         // Prefer the FIS tag parser (strips a leading [..]/{..}/(..) tag + PUA icon glyphs); fall back to the
         // legacy leading-marker trim if parsing yields nothing. Join keys elsewhere still use the RAW row.text.
         var clean:String = this.parseTag(nm).clean;
         if (clean == null || clean.length == 0) { clean = this.stripMarkers(nm); }
         return clean.toUpperCase();
      }
      // Subtitle: caliber for weapons (else a type word), then LEGENDARY / EQUIPPED flags -- derived from data we
      // HAVE (stats.type, weapon ammo, row.isLegendary, row.equipState). Nothing fabricated.
      private function cardSubStr(row:Object, stats:Object, type:String):String
      {
         var parts:Array = [];
         var cal:String = (type == "weapon" && stats != null && stats.ammo != null) ? this.stripTags(String(stats.ammo)) : "";   // #3: strip FIS tag from the card caliber sub
         if (cal.length > 0) { parts.push(cal.toUpperCase()); }
         else {
            var t:String = "";
            if (type == "weapon") { t = "WEAPON"; } else if (type == "apparel") { t = "APPAREL"; }
            else if (type == "aid") { t = "AID"; } else if (type == "ammo") { t = "AMMO"; }
            else if (type == "note") { t = "NOTE"; } else if (type == "misc") { t = "MISC"; }
            else if (this._curTab >= 0 && this._curTab < CATS.length) { t = String(CATS[this._curTab]); }
            if (t.length > 0) { parts.push(t); }
         }
         if (row != null && row.isLegendary == true) { parts.push("LEGENDARY"); }
         if (row != null && row.equipState != null && int(row.equipState) > 0) { parts.push("EQUIPPED"); }
         return parts.join(" · ");
      }
      // Legendary line: the enchantment/effect string if the push carries one (apparel/aid `effect`); weapons do
      // not carry an effect in the contract, so fall back to an honest generic label -- never invented prose.
      private function cardLegStr(stats:Object, mods:Array):String
      {
         if (stats != null && stats.effect != null && String(stats.effect).length > 0) { return String(stats.effect); }
         return "Legendary effect";
      }
      // Up to 4 stat pairs per category from PipOS_itemstats. Missing fields -> em-dash (dimmed in renderCard).
      private function cardPairsFor(row:Object, stats:Object, type:String):Array
      {
         var out:Array = []; var D:String = "—";
         if (stats == null) { return out; }
         if (type == "weapon") {
            var mode:int = this._dmgIndex % this.DMG_TYPES.length;
            var dmgVal:String = D;
            if (stats.dmg != null) {
               var base:Number = Number(stats.dmg);
               if (mode == 0) {
                  dmgVal = String(Math.round(base));                                  // BALLISTIC = vanilla display damage
                  var pellets:int = (stats.projectiles != null) ? int(stats.projectiles) : 1;
                  if (pellets > 1) { dmgVal += " x " + pellets; }                    // vanilla shotgun convention
               }
               else if (mode == 1 && stats.energyDmg != null) { dmgVal = String(Math.round(Number(stats.energyDmg))); }
               else if (mode == 2 && stats.radDmg != null) { dmgVal = String(Math.round(Number(stats.radDmg))); }
               else if (mode == 3 && stats.poisonDmg != null) { dmgVal = String(Math.round(Number(stats.poisonDmg))); }
            }
            out.push({ t: "DAMAGE · " + String(this.DMG_TYPES[mode]), v: dmgVal });
            // 0.0.43 RPM switch: show RPM/stats.rpm when the setting is on AND the push carries rpm; else FIRE RATE/
            // firerate (also the fallback when showRPM is on but an older DLL omitted rpm, so nothing breaks).
            var useRpm:Boolean = (this._showRPM && stats.rpm != null);
            out.push({ t: useRpm ? "RPM" : "FIRE RATE", v: useRpm ? String(Math.round(Number(stats.rpm))) : ((stats.firerate != null) ? String(Math.round(Number(stats.firerate))) : D) });
            out.push({ t: "RANGE",     v: (stats.range != null) ? String(Math.round(Number(stats.range))) : D });
            out.push({ t: "ACCURACY",  v: (stats.acc != null) ? String(Math.round(Number(stats.acc))) : D });
         } else if (type == "apparel") {
            // 0.0.60 EQUIPPED-COMPARISON: append (+N)/(-N) against the item currently equipped in an
            // overlapping biped slot (DLL now pushes slots+equipped per armor entry). The equipped item
            // itself gets no suffix; missing data degrades to the plain value.
            var cmp:Object = this.equippedComparatorFor(stats);
            out.push({ t: "DMG RESIST",    v: this.cmpVal(stats.dr, (cmp != null) ? cmp.dr : null, D), d: this.cmpDelta(stats.dr, (cmp != null) ? cmp.dr : null) });
            out.push({ t: "ENERGY RESIST", v: this.cmpVal(stats.er, (cmp != null) ? cmp.er : null, D), d: this.cmpDelta(stats.er, (cmp != null) ? cmp.er : null) });
            out.push({ t: "RAD RESIST",    v: this.cmpVal(stats.rr, (cmp != null) ? cmp.rr : null, D), d: this.cmpDelta(stats.rr, (cmp != null) ? cmp.rr : null) });
         } else if (type == "aid") {
            out.push({ t: "MAGNITUDE", v: (stats.magnitude != null) ? String(Math.round(Number(stats.magnitude))) : D });
            out.push({ t: "DURATION",  v: (stats.duration != null) ? ((Number(stats.duration) > 0) ? (String(Math.round(Number(stats.duration))) + "s") : "INSTANT") : D });
            out.push({ t: "ADDICTION", v: (stats.addiction != null) ? (String(Math.round(Number(stats.addiction))) + "%") : D });
         } else if (type == "ammo") {
            out.push({ t: "TYPE", v: "AMMO" });
         }
         return out;
      }
      // 0.0.60: find the stats entry of the item currently EQUIPPED in a biped slot overlapping the given
      // apparel's slots (skipping the item itself when it IS the equipped one -- comparing to self is noise).
      // Scans the pushed stats map; equipped armor entries are few, the scan is a handful of property reads.
      private function equippedComparatorFor(stats:Object):Object
      {
         if (stats == null || stats.slots == null || this._itemStats == null) { return null; }
         if (stats.equipped == true) { return null; }
         var mySlots:uint = uint(stats.slots);
         if (mySlots == 0) { return null; }
         try {
            for (var k:String in this._itemStats) {
               var e:Object = this._itemStats[k];
               if (e == null || e.equipped != true || e.slots == null) { continue; }
               if ((uint(e.slots) & mySlots) != 0) { return e; }
            }
         } catch (ec:*) {}
         return null;
      }
      // Value + comparison suffix: "24 (+5)" / "24 (-3)" / "24" (equal or no comparator). Missing own value -> dash.
      private function cmpVal(own:*, other:*, dash:String):String
      {
         if (own == null) { return dash; }
         var v:int = Math.round(Number(own));
         if (other == null) { return String(v); }
         var d:int = v - Math.round(Number(other));
         if (d == 0) { return String(v); }
         return String(v) + " (" + (d > 0 ? "+" : "") + d + ")";
      }
      // 0.0.62: comparison delta sign for color-coding (+1 better / -1 worse / 0 equal-or-N/A).
      private function cmpDelta(own:*, other:*):int
      {
         if (own == null || other == null) { return 0; }
         var d:int = Math.round(Number(own)) - Math.round(Number(other));
         return (d > 0) ? 1 : ((d < 0) ? -1 : 0);
      }
      // Neutral derived flavor: aid effect name / ammo used-by / a non-legendary apparel effect. Empty otherwise
      // (weapons + plain items get no flavor rather than invented prose).
      private function cardDescStr(row:Object, stats:Object, type:String):String
      {
         if (stats == null) { return ""; }
         if (type == "aid" && stats.effect != null && String(stats.effect).length > 0) { return "Effect: " + String(stats.effect); }
         if (type == "ammo" && stats.usedby != null && String(stats.usedby).length > 0) { return "Used by " + String(stats.usedby); }
         if (type == "apparel" && stats.effect != null && String(stats.effect).length > 0 && !(row != null && row.isLegendary == true)) { return String(stats.effect); }
         return "";
      }

      // A. Populate the QUICK ACCESS boxes from the cached root1.PipOS_favorites (fixed 7-box grid == the mockup;
      // slot i -> box i). UPDATE-ONLY: count text + icon-layer graphics only. Empty slots (formID "0") show just
      // the outline + number. Icons are font-independent vectors on the pooled _qIcons layer.
      private function renderQuick():void
      {
         if (this._qCount.length == 0 || this._qIcons == null) { return; }
         var ig:* = this._qIcons.graphics; ig.clear();
         var favs:Array = this._favs;
         for (var i:int = 0; i < 7 && i < this._qBox.length; i++) {
            var f:Object = (favs != null && i < favs.length) ? favs[i] : null;
            var populated:Boolean = (f != null && f.formID != null && String(f.formID) != "0" && String(f.formID).length > 0);
            var b:Object = this._qBox[i];
            var favClip:MovieClip = (i < this._qFavIcons.length) ? this._qFavIcons[i] as MovieClip : null;
            if (favClip != null) { favClip.visible = false; }
            if (populated) {
               var ty:String = (f.type != null) ? String(f.type) : "misc";
               var favFrame:int = (f.FavIconType != null) ? int(f.FavIconType) : 0;
               if (favClip != null && favFrame > 0) { favClip.gotoAndStop(favFrame); favClip.visible = true; }
               else { this.drawQAIcon(ig, ty, Number(b.cx), Number(b.cy), 14, Theme.PHOS_BRIGHT); }
               var cnt:Number = (f.count != null) ? Number(f.count) : 0;
               if (cnt > 1) { Theme.setText(this._qCount[i], "x" + String(int(cnt))); this._qCount[i].visible = true; }
               else { this._qCount[i].visible = false; }
               // 0.0.43 SHORT NAME (no real item icon available): a truncated uppercase name under the glyph.
               if (i < this._qName.length) { Theme.setText(this._qName[i], this.qaShortName((f.name != null) ? String(f.name) : "")); this._qName[i].visible = true; }
            } else {
               this._qCount[i].visible = false;
               if (i < this._qName.length) { this._qName[i].visible = false; }
            }
         }
      }

      // 0.0.43: derive a compact QA-box label -- tag-stripped, uppercased, and truncated to fit the ~40px box.
      // Pure string derivation (no TextField access); gated update-only by ctor_text_check.
      private function qaShortName(raw:String):String
      {
         var s:String = this.stripTags((raw != null) ? raw : "");
         s = this.trimStr(s).toUpperCase();
         if (s.length <= 8) { return s; }
         return this.trimStr(s.substr(0, 7)) + ".";   // ellipsis-style truncation to keep the box readable
      }

      // ---- A. QUICK-ACCESS vector type icons (font-independent, same style as the marker glyphs) ----
      // Dispatch by favorite `type`; each glyph is a distinct simple silhouette centred on (cx,cy).
      private function drawQAIcon(g:*, type:String, cx:Number, cy:Number, s:Number, color:uint):void
      {
         if (type == "weapon") { this.icoWeapon(g, cx, cy, s, color); }
         else if (type == "apparel") { this.icoApparel(g, cx, cy, s, color); }
         else if (type == "aid") { this.icoAid(g, cx, cy, s, color); }
         else if (type == "ammo") { this.icoAmmo(g, cx, cy, s, color); }
         else if (type == "note") { this.icoNote(g, cx, cy, s, color); }
         else if (type == "junk") { this.icoJunk(g, cx, cy, s, color); }
         else { this.icoMisc(g, cx, cy, s, color); }
      }
      private function icoWeapon(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;
         Theme.fillLine(g, cx - h, cy - h * 0.5, cx + h, cy - h * 0.5, color, 1, 1.6);
         Theme.fillLine(g, cx + h * 0.55, cy - h * 0.5, cx + h * 0.55, cy - h, color, 1, 1.6);
         Theme.fillLine(g, cx - h * 0.2, cy - h * 0.5, cx - h * 0.55, cy + h, color, 1, 1.6);
         Theme.fillLine(g, cx - h, cy - h * 0.5, cx - h, cy + h * 0.2, color, 1, 1.6);
      }
      private function icoApparel(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;
         Theme.fillLine(g, cx - h, cy - h * 0.4, cx - h * 0.45, cy - h, color, 1, 1.5);
         Theme.fillLine(g, cx - h * 0.45, cy - h, cx + h * 0.45, cy - h, color, 1, 1.5);
         Theme.fillLine(g, cx + h * 0.45, cy - h, cx + h, cy - h * 0.4, color, 1, 1.5);
         Theme.fillLine(g, cx + h, cy - h * 0.4, cx + h * 0.55, cy - h * 0.1, color, 1, 1.5);
         Theme.fillLine(g, cx + h * 0.55, cy - h * 0.1, cx + h * 0.55, cy + h, color, 1, 1.5);
         Theme.fillLine(g, cx + h * 0.55, cy + h, cx - h * 0.55, cy + h, color, 1, 1.5);
         Theme.fillLine(g, cx - h * 0.55, cy + h, cx - h * 0.55, cy - h * 0.1, color, 1, 1.5);
         Theme.fillLine(g, cx - h * 0.55, cy - h * 0.1, cx - h, cy - h * 0.4, color, 1, 1.5);
      }
      private function icoAid(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2; var t:Number = h * 0.34;
         g.lineStyle(0, 0, 0);
         g.beginFill(color, 1);   // medical cross
         g.drawRect(cx - t, cy - h, 2 * t, 2 * h);
         g.drawRect(cx - h, cy - t, 2 * h, 2 * t);
         g.endFill();
      }
      private function icoAmmo(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;
         g.lineStyle(0, 0, 0);
         g.beginFill(color, 1);   // two bullets
         for (var k:int = 0; k < 2; k++) {
            var bx:Number = cx + (k == 0 ? -h * 0.5 : h * 0.35);
            g.moveTo(bx, cy - h);                                   // tip
            g.lineTo(bx + h * 0.32, cy - h * 0.55);
            g.lineTo(bx + h * 0.32, cy + h); g.lineTo(bx - h * 0.32, cy + h);
            g.lineTo(bx - h * 0.32, cy - h * 0.55); g.lineTo(bx, cy - h);
         }
         g.endFill();
      }
      private function icoNote(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;
         Theme.frameRect(g, cx - h * 0.7, cy - h, h * 1.4, h * 2, color, 1, 1.4);
         Theme.fillLine(g, cx - h * 0.4, cy - h * 0.15, cx + h * 0.4, cy - h * 0.15, color, 1, 1.4);
         Theme.fillLine(g, cx - h * 0.4, cy + h * 0.35, cx + h * 0.4, cy + h * 0.35, color, 1, 1.4);
      }
      private function icoJunk(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;
         Theme.circleLine(g, cx, cy, h * 0.42, color, 1, 1.5, 12);
         Theme.fillLine(g, cx - h, cy, cx + h, cy, color, 1, 1.5);
         Theme.fillLine(g, cx, cy - h, cx, cy + h, color, 1, 1.5);
      }
      private function icoMisc(g:*, cx:Number, cy:Number, s:Number, color:uint):void
      {
         var h:Number = s / 2;   // small cube
         Theme.frameRect(g, cx - h * 0.7, cy - h * 0.5, h * 1.4, h * 1.2, color, 1, 1.4);
         Theme.fillLine(g, cx - h * 0.7, cy - h * 0.5, cx - h * 0.35, cy - h, color, 1, 1.4);
         Theme.fillLine(g, cx - h * 0.35, cy - h, cx + h, cy - h, color, 1, 1.4);
         Theme.fillLine(g, cx + h, cy - h, cx + h * 0.7, cy - h * 0.5, color, 1, 1.4);
         Theme.fillLine(g, cx + h, cy - h, cx + h, cy + h * 0.35, color, 1, 1.4);
         Theme.fillLine(g, cx + h, cy + h * 0.35, cx + h * 0.7, cy + h * 0.7, color, 1, 1.4);
      }

      // ---- B. TOOLTIP build (on-stage build window; geometry baked on fresh EMPTY fields, text set in handlers) ----
      private function buildTooltip():void
      {
         this._tip = new Sprite(); this._tip.mouseEnabled = false; this._tip.mouseChildren = false; this._tip.visible = false;
         addChild(this._tip);   // topmost (added after the page body); debug overlay (dev-only) may sit above
         var iw:Number = TIP_W - 2 * TIP_PAD;   // 134 interior
         // NAME: 2-line reserved band (long names wrap in the narrow box) so a long name never needs a geometry
         // write on the show path.
         this._tipName = Theme.mk(this._tip, 13, Theme.PHOS_BRIGHT, true); this._tipName.autoSize = "none"; this._tipName.multiline = true; this._tipName.wordWrap = true; this._tipName.width = iw; this._tipName.height = 30; this._tipName.x = TIP_PAD; this._tipName.y = TIP_PAD;
         this._tipSub = Theme.mk(this._tip, 10, Theme.PHOS_DIM, true); this._tipSub.autoSize = "none"; this._tipSub.width = iw; this._tipSub.height = 13; this._tipSub.x = TIP_PAD; this._tipSub.y = TIP_PAD + 30; this._tipSub.visible = false;
         // TIGHT 2-COLUMN stat lines: label (dim) at the left; value (bright) LEFT-aligned starting just after the
         // narrow label column, so the value reads right next to its label ("WT  13.1") instead of at a far edge.
         var ry0:Number = TIP_PAD + 30 + 16;
         var vColX:Number = TIP_PAD + TIP_LCOL;
         for (var i:int = 0; i < TIP_ROWS; i++) {
            var ly:Number = ry0 + i * 15;
            var l:TextField = Theme.mk(this._tip, 11, Theme.PHOS_DIM, false); l.autoSize = "none"; l.width = TIP_LCOL; l.height = 14; l.x = TIP_PAD; l.y = ly; l.visible = false; this._tipRowL.push(l);
            var v:TextField = Theme.mk(this._tip, 11, Theme.PHOS_BRIGHT, true, "left"); v.autoSize = "none"; v.width = iw - TIP_LCOL; v.height = 14; v.x = vColX; v.y = ly; v.visible = false; this._tipRowV.push(v);
         }
      }

      // ==========================================================================================
      // 0.0.61 RIGHT-CLICK CONTEXT MENU. Pooled like the tooltip: all fields created ONCE here (on-stage build
      // window); open/close/hover are UPDATE-ONLY (setText / textColor / visible / graphics / container .x/.y).
      // Item rows -> EQUIP|USE (by category), INSPECT, DROP. Folder headers -> EXPAND/COLLAPSE (this) + EXPAND
      // ALL / COLLAPSE ALL. Opening dismisses the hover box (and suppresses it while open). Trigger delivery
      // (GFx right-mouse) is runtime-unproven here -> onRowContext logs IV.rc so a test confirms it.
      private static const CTX_W:Number = 172;
      private static const CTX_ROWH:Number = 26;
      private static const CTX_PAD:Number = 5;
      private static const CTX_MAX:int = 4;
      private var _ctxMenu:Sprite;
      private var _ctxBg:Shape;
      private var _ctxHi:Shape;
      private var _ctxRowsTF:Array = [];
      private var _ctxHits:Array = [];
      private var _ctxActions:Array = [];
      private var _ctxOpen:Boolean = false;
      private var _ctxFolderKey:String = null;
      private var _curFolderKeys:Array = [];   // this tab's folder keys (stashed in groupPairs; for Expand/Collapse All)

      private function buildContextMenu():void
      {
         this._ctxMenu = new Sprite(); this._ctxMenu.visible = false; addChild(this._ctxMenu);   // topmost (after tooltip)
         this._ctxBg = new Shape(); this._ctxMenu.addChild(this._ctxBg);
         this._ctxHi = new Shape(); this._ctxMenu.addChild(this._ctxHi);   // hover highlight (below text)
         this._ctxRowsTF = []; this._ctxHits = [];
         for (var i:int = 0; i < CTX_MAX; i++) {
            var ry:Number = CTX_PAD + i * CTX_ROWH;
            var tf:TextField = Theme.mk(this._ctxMenu, 12, Theme.PHOS, true); tf.autoSize = "none"; tf.width = CTX_W - 2 * CTX_PAD - 12; tf.height = 18; tf.x = CTX_PAD + 10; tf.y = ry + 4; tf.mouseEnabled = false; tf.visible = false; this._ctxRowsTF.push(tf);
            var hs:Sprite = new Sprite(); hs.graphics.beginFill(0, 0.004); hs.graphics.drawRect(CTX_PAD, ry, CTX_W - 2 * CTX_PAD, CTX_ROWH); hs.graphics.endFill();
            hs.name = "cx" + i; hs.buttonMode = true; hs.visible = false;
            hs.addEventListener(MouseEvent.MOUSE_DOWN, this.onCtxRowClick);
            hs.addEventListener(MouseEvent.ROLL_OVER, this.onCtxRowOver);
            hs.addEventListener(MouseEvent.ROLL_OUT, this.onCtxRowOut);
            this._ctxMenu.addChild(hs); this._ctxHits.push(hs);
         }
      }

      // PipList right-click -> decide folder vs item menu. Selection (items) + folder tag capture happen here.
      private function onRowContext(idx:int, entry:Object, ex:Number, ey:Number):void
      {
         Theme.life("IV.rc");   // breadcrumb: GFx actually delivered a right-click to a row
         this.hideTooltip();
         var opts:Array = [];
         if (entry != null && entry.__folder == true) {
            this._ctxFolderKey = (entry.tag != null) ? String(entry.tag) : null;
            if (entry.collapsed == true) { opts.push({ label:"EXPAND", act:"expand" }); }
            else { opts.push({ label:"COLLAPSE", act:"collapse" }); }
            opts.push({ label:"EXPAND ALL", act:"expandall" });
            opts.push({ label:"COLLAPSE ALL", act:"collapseall" });
         } else {
            this._ctxFolderKey = null;
            if (this._list != null) { this._list.selectIndex(idx); }   // right-click selects the item it targets
            var eq:String = this.equipUseLabel();
            if (eq != null) { opts.push({ label:eq, act:"equip" }); }
            opts.push({ label:"INSPECT", act:"inspect" });
            opts.push({ label:"DROP", act:"drop" });
         }
         this.openContextMenu(opts, ex, ey);
      }

      // EQUIP for weapons/apparel, USE for aid; MISC/JUNK/MODS/AMMO carry only INSPECT + DROP (no dead action).
      private function equipUseLabel():String
      {
         if (this._curTab == 0 || this._curTab == 1) { return "EQUIP"; }
         if (this._curTab == 2) { return "USE"; }
         return null;
      }

      private function openContextMenu(opts:Array, ex:Number, ey:Number):void
      {
         if (this._ctxMenu == null) { return; }
         var n:int = Math.min(opts.length, CTX_MAX);
         this._ctxActions = [];
         for (var i:int = 0; i < CTX_MAX; i++) {
            var tf:TextField = this._ctxRowsTF[i] as TextField; var hs:Sprite = this._ctxHits[i] as Sprite;
            if (i < n) {
               Theme.setText(tf, String(opts[i].label)); tf.textColor = Theme.PHOS; tf.visible = true; hs.visible = true;
               this._ctxActions.push(String(opts[i].act));
            } else { tf.visible = false; hs.visible = false; }
         }
         var h:Number = 2 * CTX_PAD + n * CTX_ROWH;
         var g:* = this._ctxBg.graphics; g.clear();
         g.beginFill(Theme.GROUND, 0.97); g.drawRoundRect(0, 0, CTX_W, h, 6, 6); g.endFill();
         Theme.frameRect(g, 0, 0, CTX_W, h, Theme.PHOS, 0.55);
         this._ctxHi.graphics.clear();
         // position at the cursor (page-local), clamped inside the content frame
         var p:Point = this.globalToLocal(new Point(ex, ey));
         var px:Number = p.x + 2, py:Number = p.y + 2;
         if (px + CTX_W > Theme.CR) { px = p.x - CTX_W - 2; }
         if (py + h > Theme.BB) { py = Theme.BB - h; }
         if (px < Theme.CX) { px = Theme.CX; }
         if (py < Theme.FY) { py = Theme.FY; }
         this._ctxMenu.x = px; this._ctxMenu.y = py;
         this._ctxMenu.visible = true; this._ctxOpen = true;
         if (stage != null) { stage.addEventListener(MouseEvent.MOUSE_DOWN, this.onCtxStageDown, true); }   // capture: close on outside click
      }

      // 0.0.69: the stage CAPTURE handler now dispatches menu actions BY COORDINATES instead of trusting
      // display-list targets (0.0.68 field trail: IV.rc fired but row clicks produced zero action marks --
      // GFx target/contains behavior over the pooled menu proved unreliable). Any mouse-down while the menu
      // is open resolves here: inside the menu -> run that row's action; outside -> just close.
      private function onCtxStageDown(e:MouseEvent):void
      {
         if (this._ctxMenu == null || !this._ctxMenu.visible) { return; }
         var lp:Point = this._ctxMenu.globalToLocal(new Point(e.stageX, e.stageY));
         var n:int = this._ctxActions.length;
         var h:Number = 2 * CTX_PAD + n * CTX_ROWH;
         if (lp.x >= 0 && lp.x <= CTX_W && lp.y >= 0 && lp.y <= h) {
            var i:int = int(Math.floor((lp.y - CTX_PAD) / CTX_ROWH));
            var act:String = (i >= 0 && i < n) ? String(this._ctxActions[i]) : null;
            Theme.life("CX." + (act != null ? act : "pad"));
            this.closeContextMenu();
            if (act != null) { this.doContextAction(act); }
         } else {
            Theme.life("CX.out");
            this.closeContextMenu();
         }
      }
      private function onCtxRowClick(e:MouseEvent):void
      {
         // 0.0.69: retained as a FALLBACK only (the capture handler above normally acts first and closes).
         if (!this._ctxOpen) { return; }
         var i:int = int(String(e.currentTarget.name).substr(2));   // "cx2" -> 2
         var act:String = (i >= 0 && i < this._ctxActions.length) ? String(this._ctxActions[i]) : null;
         Theme.life("CXr." + (act != null ? act : "null"));
         this.closeContextMenu();
         if (act != null) { this.doContextAction(act); }
      }
      private function onCtxRowOver(e:MouseEvent):void
      {
         var i:int = int(String(e.currentTarget.name).substr(2));
         var ry:Number = CTX_PAD + i * CTX_ROWH;
         var g:* = this._ctxHi.graphics; g.clear();
         g.beginFill(Theme.PHOS, 0.16); g.drawRect(CTX_PAD, ry, CTX_W - 2 * CTX_PAD, CTX_ROWH); g.endFill();
         if (i >= 0 && i < this._ctxRowsTF.length) { (this._ctxRowsTF[i] as TextField).textColor = Theme.PHOS_BRIGHT; }
      }
      private function onCtxRowOut(e:MouseEvent):void
      {
         this._ctxHi.graphics.clear();
         var i:int = int(String(e.currentTarget.name).substr(2));
         if (i >= 0 && i < this._ctxRowsTF.length) { (this._ctxRowsTF[i] as TextField).textColor = Theme.PHOS; }
      }
      private function closeContextMenu():void
      {
         if (!this._ctxOpen && (this._ctxMenu == null || !this._ctxMenu.visible)) { return; }
         if (this._ctxMenu != null) { this._ctxMenu.visible = false; this._ctxHi.graphics.clear(); }
         this._ctxOpen = false; this._ctxFolderKey = null;
         this._ctxActions = [];   // 0.0.69: dead menu carries no actions (guards the fallback row handler)
         if (stage != null) { stage.removeEventListener(MouseEvent.MOUSE_DOWN, this.onCtxStageDown, true); }
      }
      private function doContextAction(act:String):void
      {
         if (act == "equip") {
            var oi:int = this.invIdx(this._list.selectedIndex);
            if (oi >= 0) { this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "SelectItem", oi); }
         } else if (act == "inspect") { this.doInspect(); }
         else if (act == "drop") { this.doDrop(); }
         else if (act == "expand") { if (this._ctxFolderKey != null) { this.setFolderCollapsed(this._curTab, this._ctxFolderKey, false); this.rebuildAfterFolders(); } }
         else if (act == "collapse") { if (this._ctxFolderKey != null) { this.setFolderCollapsed(this._curTab, this._ctxFolderKey, true); this.rebuildAfterFolders(); } }
         else if (act == "expandall") { this.setAllFolders(false); }
         else if (act == "collapseall") { this.setAllFolders(true); }
      }
      private function setAllFolders(collapsed:Boolean):void
      {
         if (this._curFolderKeys == null) { return; }
         for (var i:int = 0; i < this._curFolderKeys.length; i++) { this.setFolderCollapsed(this._curTab, String(this._curFolderKeys[i]), collapsed); }
         this.rebuildAfterFolders();
      }
      private function rebuildAfterFolders():void
      {
         this.sfx("UIMenuPrevNext");
         if (this._lastData != null) { this.rebuildList(this._lastData); this.updateInvTitle(); this.drawSortIndicator(); }
      }

      // ---- B. TOOLTIP interaction (UPDATE-ONLY: setText/textColor/visible + panel graphics + Sprite-container
      // .x/.y. NO TextField geometry write anywhere below; the pooled fields keep the geometry baked in buildTooltip.
      private var _tipH:Number = 60;   // last drawn panel height (drives clamp; not a TextField geometry write)
      // Row hover (from PipList.onHover): map the hovered display index -> InvItems row -> name+formID -> tooltip.
      private function onListHover(i:int):void
      {
         if (i < 0) { this.hideTooltip(); return; }
         var oi:int = this.invIdx(i);
         var row:Object = (this._lastData != null && this._lastData.InvItems != null && oi >= 0 && oi < this._lastData.InvItems.length) ? this._lastData.InvItems[oi] : null;
         if (row == null) { this.hideTooltip(); return; }
         var nm:String = (row.text != null) ? String(row.text) : "";
         var fid:String = (row.formID != null) ? String(row.formID) : "";
         this.showTooltip(nm, fid, "");
      }
      // QA box hover -> tooltip with the favorite's FULL name (solves the box-can't-show-long-name ask).
      private function onQAOver(e:MouseEvent):void
      {
         var i:int = int(String(e.currentTarget.name).substr(1));
         var f:Object = (this._favs != null && i >= 0 && i < this._favs.length) ? this._favs[i] : null;
         if (f == null || f.formID == null || String(f.formID) == "0" || String(f.formID).length == 0) { this.hideTooltip(); return; }
         var nm:String = (f.name != null) ? String(f.name) : "";
         this.showTooltip(nm, String(f.formID), (f.type != null) ? String(f.type) : "");
      }
      private function onQAOut(e:MouseEvent):void { this.hideTooltip(); }
      private function hideTooltip():void { if (this._tip != null) { this._tip.visible = false; } }

      // Core show: joins stats by formID, fills the pooled fields, sizes the panel by line count, follows the cursor.
      private function showTooltip(name:String, formID:String, hintType:String):void
      {
         if (this._tip == null || this._tipName == null) { return; }
         if (this._ctxOpen) { return; }   // 0.0.61: the context menu temporarily suppresses the hover box
         var stats:Object = null;
         if (formID != null && String(formID).length > 0 && String(formID) != "0" && this._itemStats != null) {
            try { stats = this._itemStats[this.fidKey(formID)]; } catch (e1:*) { stats = null; }
         }
         var type:String = (stats != null && stats.type != null) ? String(stats.type) : ((hintType != null) ? hintType : "");
         // DISPLAY the tag-stripped clean name; JOIN (tipLinesFor -> PipOS_iteminfo) still uses the RAW `name`.
         var dispName:String = this.parseTag((name != null) ? name : "").clean;
         if (dispName.length == 0 && name != null) { dispName = name; }
         Theme.setText(this._tipName, dispName);
         var sub:String = this.tipSubStr(stats, type);
         if (sub.length > 0) { Theme.setText(this._tipSub, sub); this._tipSub.visible = true; } else { this._tipSub.visible = false; }
         var lines:Array = this.tipLinesFor(name, stats, type);
         var n:int = 0;
         for (var i:int = 0; i < this._tipRowL.length; i++) {
            if (i < lines.length) {
               Theme.setText(this._tipRowL[i], String(lines[i].t)); this._tipRowL[i].visible = true;
               Theme.setText(this._tipRowV[i], String(lines[i].v)); this._tipRowV[i].visible = true;
               n++;
            } else { this._tipRowL[i].visible = false; this._tipRowV[i].visible = false; }
         }
         this.drawTipPanel(n);
         this.positionTip();
         this._tip.visible = true;
      }
      // Panel background sized to the visible line count (graphics-only; height is a local Number, not a field write).
      private function drawTipPanel(n:int):void
      {
         var ry0:Number = TIP_PAD + 30 + 16;
         var bottom:Number;
         if (n > 0) { bottom = ry0 + n * 15; }
         else if (this._tipSub.visible) { bottom = TIP_PAD + 30 + 15; }
         else { bottom = TIP_PAD + 30; }
         this._tipH = bottom + TIP_PAD;
         var g:* = this._tip.graphics; g.clear();
         Theme.panel(g, 0, 0, TIP_W, this._tipH, 0.5);
      }
      // Reposition the Sprite CONTAINER by .x/.y (allowed -- moving a Sprite never reformats text). Clamped to the
      // mockup canvas so the tooltip never leaves the visible frame; flips left of the cursor near the right edge.
      private function positionTip():void
      {
         if (this._tip == null) { return; }
         var minX:Number = Theme.FX + 4; var maxX:Number = Theme.FX + Theme.SW - TIP_W - 4;
         var minY:Number = Theme.FY + 4; var maxY:Number = Theme.FY + Theme.SH - this._tipH - 4;
         var ox:Number = this.mouseX + 18; var oy:Number = this.mouseY + 18;
         if (ox > maxX) { ox = this.mouseX - TIP_W - 18; }   // flip to the cursor's left
         if (ox < minX) { ox = minX; } if (ox > maxX) { ox = maxX; }
         if (oy < minY) { oy = minY; } if (oy > maxY) { oy = maxY; }
         this._tip.x = ox; this._tip.y = oy;
      }
      // Cursor follow: reposition only while visible (cheap; Sprite .x/.y move).
      private function onMouseMove(e:MouseEvent):void { if (this._tip != null && this._tip.visible) { this.positionTip(); } }

      // Sub-type line (caliber for weapons, else the category word). Pure string derivation (no TextField access).
      private function tipSubStr(stats:Object, type:String):String
      {
         if (type == "weapon" && stats != null && stats.ammo != null && String(stats.ammo).length > 0) { return this.stripTags(String(stats.ammo)).toUpperCase(); }   // #3: strip FIS tag from tooltip caliber
         if (type == "weapon") { return "WEAPON"; }
         if (type == "apparel") { return "APPAREL"; }
         if (type == "aid") { return "AID"; }
         if (type == "ammo") { return "AMMO"; }
         if (type == "note") { return "NOTE"; }
         if (type == "misc") { return "MISC"; }
         if (type == "junk") { return "JUNK"; }
         return "";
      }
      // WT/VAL (from PipOS_iteminfo by bare name) + 1-2 key stats by type (from PipOS_itemstats). Missing -> omitted
      // (never a row of dashes). Pure derivation; capped by TIP_ROWS in the pooled row set.
      private function tipLinesFor(name:String, stats:Object, type:String):Array
      {
         var out:Array = [];
         var wStr:String = "", vStr:String = "";
         if (this._itemInfo != null && name != null && name.length > 0) {
            var info:Object = null; try { info = this._itemInfo[name]; } catch (e1:*) { info = null; }
            if (info != null) { if (info.w != null) { wStr = String(info.w); } if (info.v != null) { vStr = String(info.v); } }
         }
         if (wStr.length > 0) { out.push({ t:"WT", v:wStr }); }
         if (vStr.length > 0) { out.push({ t:"VAL", v:vStr }); }
         if (stats != null) {
            // 0.0.43: abbreviated labels (DMG/RATE/DR/RAD) so each value hugs its label in the compact 2-column.
            if (type == "weapon") {
               if (stats.dmg != null) { out.push({ t:"DMG", v:String(Math.round(Number(stats.dmg))) }); }
               // 0.0.43 RPM switch: "RPM"/stats.rpm when the setting is on AND rpm is present; else "RATE"/firerate.
               if (this._showRPM && stats.rpm != null) { out.push({ t:"RPM", v:String(Math.round(Number(stats.rpm))) }); }
               else if (stats.firerate != null) { out.push({ t:"RATE", v:String(Math.round(Number(stats.firerate))) }); }
            } else if (type == "apparel") {
               if (stats.dr != null) { out.push({ t:"DR", v:String(Math.round(Number(stats.dr))) }); }
               if (stats.rr != null) { out.push({ t:"RAD", v:String(Math.round(Number(stats.rr))) }); }
            } else if (type == "aid") {
               if (stats.effect != null && String(stats.effect).length > 0) { out.push({ t:"EFFECT", v:String(stats.effect) }); }
            } else if (type == "ammo") {
               if (stats.usedby != null && String(stats.usedby).length > 0) { out.push({ t:"USED BY", v:String(stats.usedby) }); }
            }
         }
         return out;
      }

      // ---- A. QA CLICK: the box's real, non-dead action -- SELECT the favorite's item in the inventory list. If
      // it's in the current category, select it directly; otherwise switch to its category and select on rebuild.
      private function onQAClick(e:MouseEvent):void
      {
         var i:int = int(String(e.currentTarget.name).substr(1));
         var f:Object = (this._favs != null && i >= 0 && i < this._favs.length) ? this._favs[i] : null;
         if (f == null || f.formID == null || String(f.formID) == "0" || String(f.formID).length == 0) { return; }   // empty slot: no-op
         var fid:String = String(f.formID);
         var di:int = this.findDisplayIndexByFormID(fid);
         if (di >= 0) { this.sfx("UIMenuOK"); this._list.selectIndex(di); return; }   // in current category -> select now
         // #6: the item may be in THIS category but hidden inside a collapsed folder. Open its folder, rebuild, select.
         if (this._lastData != null && this.openFolderForFormID(fid)) {
            this.rebuildList(this._lastData); this.updateInvTitle(); this.drawSortIndicator();
            di = this.findDisplayIndexByFormID(fid);
            if (di >= 0) { this.sfx("UIMenuOK"); this._list.selectIndex(di); return; }
         }
         // Not in the current category: switch to the favorite's category, then select it on the next rebuild.
         var tab:int = this.favCategory((f.type != null) ? String(f.type) : "");
         if (tab < 0 || tab == this._curTab) { return; }
         this._pendingFavFormID = fid;
         this.sfx("UIMenuPrevNext");
         var m:Object = this.acquireMenu();
         var routed:Boolean = false;
         if (m != null) { try { m.TryToSetTab(tab); routed = true; } catch (er:*) { routed = false; } }
         if (!routed) { BGSExternalInterface.call(this.codeObj, "onNewTab", tab); }
      }
      // Favorite `type` -> category tab index (matches CATS order). note groups under MISC; junk under JUNK.
      private function favCategory(type:String):int
      {
         if (type == "weapon") { return 0; }
         if (type == "apparel") { return 1; }
         if (type == "aid") { return 2; }
         if (type == "misc" || type == "note") { return 3; }
         if (type == "junk") { return 4; }
         if (type == "ammo") { return 6; }
         return -1;
      }
      // Find the current display-list index whose InvItems row matches this decimal formID (no TextField access).
      private function findDisplayIndexByFormID(fid:String):int
      {
         if (fid == null || this._lastData == null || this._lastData.InvItems == null || this._invMap == null) { return -1; }
         for (var k:int = 0; k < this._invMap.length; k++) {
            var oi:int = int(this._invMap[k]);
            var row:Object = (oi >= 0 && oi < this._lastData.InvItems.length) ? this._lastData.InvItems[oi] : null;
            if (row != null && row.formID != null && String(row.formID) == fid) { return k; }
         }
         return -1;
      }
      // #6: open the folder that CONTAINS the InvItems row matching this formID (so a targeted select -- a favorite
      // QA click / cross-category pending select -- can reach an item hidden inside a collapsed folder). Returns true
      // if a currently-collapsed folder was opened. Pure state flip (no fields/geometry).
      private function openFolderForFormID(fid:String):Boolean
      {
         if (fid == null || !this._foldersOn || this._lastData == null || this._lastData.InvItems == null) { return false; }
         var src:Array = this._lastData.InvItems;
         for (var i:int = 0; i < src.length; i++) {
            var row:Object = src[i];
            if (row == null || row.formID == null || String(row.formID) != fid) { continue; }
            var pt:Object = this.parseTag(this.itemName(row));
            var key:String = (pt.tag != null) ? this.folderBucket(String(pt.tag), this._curTab) : "MISC";
            if (this.isFolderCollapsed(this._curTab, key)) { this.setFolderCollapsed(this._curTab, key, false); return true; }
            return false;
         }
         return false;
      }

      // ============================================================================================
      // FULLSCREEN INSPECT OVERLAY
      // ---- POOL BUILDER (called ONCE from buildText, the proven on-stage build window). Creates every overlay
      // field with baked geometry (autoSize="none", geometry-before-text) so no interaction-reachable handler
      // ever creates a field or writes TextField geometry. Deliberately NOT in ctor_text_check NEW_HANDLERS.
      private function buildInspect():void
      {
         var cx:Number = Theme.FX + Theme.SW / 2;   // canvas centre (root1-local; page transform is identity)
         this._insLay = new Sprite(); this._insLay.visible = false; this._insLay.alpha = 0; addChild(this._insLay);   // topmost page child

         // Dim phosphor veil + the two panel backgrounds are drawn on _insLay's OWN graphics (which render BEHIND
         // all its children, so the emblem/title/rows sit on top). The veil is drawn FIRST, the panels AFTER, so
         // the panels stack above the veil. _insLay stays mouseEnabled: its veil fill catches clicks, so the list
         // beneath is inert while inspecting. A dim veil is an honest stand-in for the mockup's backdrop-blur.
         var lg:* = this._insLay.graphics;
         lg.beginFill(Theme.GROUND, 0.72); lg.drawRect(Theme.FX, Theme.FY, Theme.SW, Theme.SH); lg.endFill();
         lg.beginFill(Theme.PHOS_FAINT, 0.10); lg.drawRect(Theme.FX, Theme.FY, Theme.SW, Theme.SH); lg.endFill();
         var spx:Number = Theme.mx(60);  var spy:Number = Theme.my(452); var spw:Number = Theme.ms(330);
         var mpx:Number = Theme.mx(1210); var mpw:Number = Theme.ms(330);
         Theme.panel(lg, spx, spy, spw, Theme.ms(300), 0.5);
         Theme.panel(lg, mpx, spy, mpw, Theme.ms(300), 0.5);

         // Centre emblem container. Drawn origin-centred so WHEEL scaling (_insEmblem.scale) zooms about centre.
         this._insEmblem = new Sprite(); this._insEmblem.mouseEnabled = false; this._insEmblem.mouseChildren = false;
         this._insEmblem.x = cx; this._insEmblem.y = Theme.my(430); this._insLay.addChild(this._insEmblem);

         // TITLE: fixed full-width centred box (long names centre without any geometry write on the show path).
         this._insTitle = Theme.mk(this._insLay, 22, Theme.PHOS_BRIGHT, true, "center");
         this._insTitle.autoSize = "none"; this._insTitle.width = Theme.SW; this._insTitle.height = 30;
         this._insTitle.x = Theme.FX; this._insTitle.y = Theme.my(54);
         var itf:* = this._insTitle.defaultTextFormat; itf.letterSpacing = 1.6; this._insTitle.defaultTextFormat = itf;
         Theme.glow(this._insTitle, Theme.PHOS_BRIGHT, 1); this._insTitle.visible = false;

         // LEGENDARY badge (pulsing box) + effect line, centred under the title. Whole container hidden off-legendary.
         this._insLeg = new Sprite(); this._insLeg.mouseEnabled = false; this._insLeg.mouseChildren = false; this._insLeg.visible = false; this._insLay.addChild(this._insLeg);
         this._insBadge = new Sprite(); this._insLeg.addChild(this._insBadge);
         var bg:* = this._insBadge.graphics;
         Theme.frameRect(bg, cx - 150, Theme.my(90), 96, 20, 0xD6FFBE, 0.65);
         Theme.sparkle(bg, cx - 138, Theme.my(100), 4, 0xEAFFDC);
         var lb:TextField = Theme.mk(this._insBadge, 10, 0xEAFFDC, true, "center");
         lb.autoSize = "none"; lb.width = 78; lb.height = 16; lb.x = cx - 132; lb.y = Theme.my(92);
         var lbf:* = lb.defaultTextFormat; lbf.letterSpacing = 2.2; lb.defaultTextFormat = lbf; Theme.setText(lb, "LEGENDARY");
         this._insLegText = Theme.mk(this._insLeg, 13, 0xD9F7C8, false, "left");
         this._insLegText.autoSize = "none"; this._insLegText.width = 260; this._insLegText.height = 18; this._insLegText.x = cx - 46; this._insLegText.y = Theme.my(91);
         Theme.glow(this._insLegText, 0xBEFFAA, 1);

         // STATS panel (left) + CURRENT MODS panel (right) headers + pooled rows (panel bgs drawn above).
         this._insStatsHdr = Theme.mk(this._insLay, 13, Theme.PHOS, true, "left");
         this._insStatsHdr.autoSize = "none"; this._insStatsHdr.width = spw - 32; this._insStatsHdr.height = 18; this._insStatsHdr.x = spx + 16; this._insStatsHdr.y = spy + 12;
         var shf:* = this._insStatsHdr.defaultTextFormat; shf.letterSpacing = 1.8; this._insStatsHdr.defaultTextFormat = shf; Theme.setText(this._insStatsHdr, "STATS");
         this._insModsHdr = Theme.mk(this._insLay, 13, Theme.PHOS, true, "left");
         this._insModsHdr.autoSize = "none"; this._insModsHdr.width = mpw - 32; this._insModsHdr.height = 18; this._insModsHdr.x = mpx + 16; this._insModsHdr.y = spy + 12;
         var mhf:* = this._insModsHdr.defaultTextFormat; mhf.letterSpacing = 1.8; this._insModsHdr.defaultTextFormat = mhf; Theme.setText(this._insModsHdr, "CURRENT MODS");
         var rowTop:Number = spy + 40; var rowH:Number = 26; var innerS:Number = spw - 32; var innerM:Number = mpw - 32;
         for (var i:int = 0; i < INS_STAT_ROWS; i++) {
            var ry:Number = rowTop + i * rowH;
            var sl:TextField = Theme.mk(this._insLay, 12, Theme.PHOS_DIM, false, "left");
            sl.autoSize = "none"; sl.width = innerS * 0.62; sl.height = 18; sl.x = spx + 16; sl.y = ry; sl.visible = false; this._insStatL.push(sl);
            var sv:TextField = Theme.mk(this._insLay, 13, Theme.PHOS_BRIGHT, true, "right");
            sv.autoSize = "none"; sv.width = innerS * 0.38 - 16; sv.height = 18; sv.x = spx + 16 + innerS * 0.62; sv.y = ry; sv.visible = false; this._insStatV.push(sv);
            var mr:TextField = Theme.mk(this._insLay, 12, Theme.PHOS, false, "left");
            mr.autoSize = "none"; mr.width = innerM; mr.height = 18; mr.x = mpx + 16; mr.y = ry; mr.visible = false; this._insModRows.push(mr);
         }

         // KEYBAR (mockup): W PREV / S NEXT / WHEEL ZOOM / R EXIT. Static text -> built ONCE here (Theme.keycap
         // bakes geometry-before-text on fresh fields, build-window safe). Centre the whole strip via Sprite .x.
         this._insKeys = new Sprite(); this._insKeys.mouseEnabled = false; this._insKeys.mouseChildren = false; this._insLay.addChild(this._insKeys);
         var kx:Number = 0; var gap:Number = 26;
         kx += Theme.keycap(this._insKeys, kx, 0, "W", "PREV") + gap;
         kx += Theme.keycap(this._insKeys, kx, 0, "S", "NEXT") + gap;
         kx += Theme.keycap(this._insKeys, kx, 0, "WHEEL", "ZOOM") + gap;
         kx += Theme.keycap(this._insKeys, kx, 0, "R", "EXIT");
         this._insKeys.x = cx - kx / 2; this._insKeys.y = Theme.my(852);
      }

      // Graphics-only: draw the large centred vector item emblem for `type` into _insEmblem (origin-centred so the
      // WHEEL scale zooms about the middle). Honest stand-in for a real 3D item capture we do not have.
      private function renderInspectEmblem(type:String):void
      {
         if (this._insEmblem == null) { return; }
         var g:* = this._insEmblem.graphics; g.clear();
         Theme.brackets(g, -150, -104, 300, 208, 30, Theme.PHOS, 0.35);          // frame
         Theme.circleLine(g, 0, 20, 132, Theme.PHOS_FAINT, 0.5, 1, 32);   // stage ring
         var col:uint = this._insIsLeg ? Theme.WARN : Theme.PHOS_BRIGHT;
         this.drawQAIcon(g, type, 0, 0, 150, col);                               // big type silhouette
      }

      // ---- ENTER: gate (weapons/apparel only), snapshot the selected item, fill panels, fade the overlay in.
      private function enterInspect():void
      {
         if (this._inspecting || this._insLay == null) { return; }
         if (this._list == null || this._list.selectedIndex < 0) { return; }
         this._inspecting = true;
         this.hideTooltip();
         this._insZoom = 1; this._insEmblem.scaleX = 1; this._insEmblem.scaleY = 1;
         this.renderInspect();
         this._insLay.visible = true; this._insFadeDir = 1; this._insPulse = 0;
         this.sfx("UIMenuOK");
         if (this._insTicker == null) { this._insTicker = new Ticker(this, this.onInspectTick); }
         this._insTicker.start();
      }

      // ---- EXIT: fade the overlay out (the tick hides + stops it at alpha 0). Idempotent.
      private function exitInspect():void
      {
         if (!this._inspecting || this._insLay == null) { return; }
         this._inspecting = false;
         this._insFadeDir = -1;
         this.sfx("UIMenuCancel");
         if (this._insTicker == null) { this._insTicker = new Ticker(this, this.onInspectTick); }
         this._insTicker.start();
      }

      // ---- CYCLE prev/next within the current category, re-populating the overlay (mockup cycleInspect). Moves the
      // real list selection (so the underlying card/3D stay in sync), then refills the overlay panels + emblem.
      private function cycleInspect(delta:int):void
      {
         if (!this._inspecting || this._list == null) { return; }
         var n:int = this._list.length; if (n <= 0) { return; }
         var next:int = (this._list.selectedIndex + delta + n) % n;
         if (next != this._list.selectedIndex) { this._list.selectIndex(next); }   // fires onListSel -> card/3D
         this.renderInspect();
      }

      // ---- WHEEL zoom (only while inspecting): scale the emblem CONTAINER (a Sprite scale, never a TextField geom).
      private function onInspectWheel(e:MouseEvent):void
      {
         if (!this._inspecting || this._insEmblem == null) { return; }
         this._insZoom = this._insZoom * ((e.delta < 0) ? 0.90 : 1.10);
         if (this._insZoom < 0.5) { this._insZoom = 0.5; }
         if (this._insZoom > 2.4) { this._insZoom = 2.4; }
         this._insEmblem.scaleX = this._insZoom; this._insEmblem.scaleY = this._insZoom;
      }

      // ---- FADE + PULSE tick (time-based; honours the 30fps root). Drives the container alpha in/out and, while
      // shown, the subtle legendary-badge alpha pulse. UPDATE-ONLY (Sprite .alpha; no TextField geometry).
      private function onInspectTick(dt:Number):void
      {
         if (this._insFadeDir != 0) {
            this._insFade += (dt / 0.24) * this._insFadeDir;
            if (this._insFade < 0) { this._insFade = 0; }
            if (this._insFade > 1) { this._insFade = 1; }
            var e:Number = this._insFade * this._insFade * (3 - 2 * this._insFade);   // smoothstep
            this._insLay.alpha = e;
            if (this._insFadeDir > 0 && this._insFade >= 1) { this._insFadeDir = 0; }
            else if (this._insFadeDir < 0 && this._insFade <= 0) {
               this._insFadeDir = 0; this._insLay.visible = false; this._insTicker.stop(); return;
            }
         }
         if (this._insLay.visible && this._insIsLeg && this._insBadge != null) {
            this._insPulse += dt; this._insBadge.alpha = 0.62 + 0.38 * (0.5 + 0.5 * Math.sin(this._insPulse * 2.6));
         }
      }

      // ---- FILL the overlay from the DLL push (same join as renderCard). UPDATE-ONLY: .text/.textColor/.visible +
      // the emblem graphics. Join key is the selected row's decimal formID against PipOS_itemstats/itemmods.
      private function renderInspect():void
      {
         if (this._insTitle == null) { return; }
         var row:Object = this._selRow;
         var stats:Object = null; var mods:Array = null;
         if (row != null && row.formID != null && this._itemStats != null) { try { stats = this._itemStats[this.fidKey(row.formID)]; } catch (e1:*) { stats = null; } }
         if (row != null && row.formID != null && this._itemMods != null) { try { mods = this._itemMods[this.fidKey(row.formID)] as Array; } catch (e2:*) { mods = null; } }
         var type:String = (stats != null && stats.type != null) ? String(stats.type) : ((this._curTab == 1) ? "apparel" : "weapon");

         Theme.setText(this._insTitle, this.cardName(row)); this._insTitle.visible = true;

         // Legendary badge (pulsing) + effect line; whole container hidden when the item is not legendary.
         this._insIsLeg = (row != null && row.isLegendary == true);
         if (this._insIsLeg) { this._insLeg.visible = true; Theme.setText(this._insLegText, this.cardLegStr(stats, mods)); }
         else { this._insLeg.visible = false; this._insBadge.alpha = 1; }

         // Emblem (gold for legendaries via _insIsLeg).
         this.renderInspectEmblem(type);

         // STATS panel: the per-type stat pairs + AMMO/WEIGHT/VALUE, capped to the pooled rows.
         var lines:Array = this.inspectStatLines(row, stats, type);
         var D:String = "—";
         for (var i:int = 0; i < this._insStatL.length; i++) {
            if (i < lines.length) {
               (this._insStatL[i] as TextField).visible = true; Theme.setText(this._insStatL[i] as TextField, String(lines[i].t));
               var vv:String = String(lines[i].v);
               var vf:TextField = this._insStatV[i] as TextField; vf.visible = true; Theme.setText(vf, vv);
               vf.textColor = (vv == D) ? Theme.PHOS_DIM : Theme.PHOS_BRIGHT;
            } else { (this._insStatL[i] as TextField).visible = false; (this._insStatV[i] as TextField).visible = false; }
         }

         // CURRENT MODS panel: the installed-mod names, else an honest "No modifications" (never invented).
         var nmods:int = (mods != null) ? mods.length : 0;
         for (var m:int = 0; m < this._insModRows.length; m++) {
            var mf:TextField = this._insModRows[m] as TextField;
            if (nmods > 0 && m < nmods) { mf.visible = true; mf.textColor = Theme.PHOS; Theme.setText(mf, "· " + String(mods[m])); }
            else if (nmods == 0 && m == 0) { mf.visible = true; mf.textColor = Theme.PHOS_DIM; Theme.setText(mf, "No modifications"); }
            else { mf.visible = false; }
         }
      }

      // Pure derivation (no TextField access): the stat lines for the inspect Stats panel -- the per-type pairs from
      // PipOS_itemstats (via cardPairsFor) plus AMMO (weapons) and WEIGHT/VALUE (from PipOS_iteminfo by bare name).
      private function inspectStatLines(row:Object, stats:Object, type:String):Array
      {
         var out:Array = this.cardPairsFor(row, stats, type);   // up to 4 typed pairs (em-dash on miss)
         if (type == "weapon" && stats != null && stats.ammo != null && String(stats.ammo).length > 0) { out.push({ t:"AMMO", v:String(stats.ammo).toUpperCase() }); }
         var bare:String = (row != null && row.text != null) ? String(row.text) : "";
         if (this._itemInfo != null && bare.length > 0) {
            var info:Object = null; try { info = this._itemInfo[bare]; } catch (e1:*) { info = null; }
            if (info != null) {
               if (info.w != null) { out.push({ t:"WEIGHT", v:String(info.w) }); }
               if (info.v != null) { out.push({ t:"VALUE", v:String(info.v) }); }
            }
         }
         return out;
      }

      private function doInspect():void
      {
         if (this._inspecting) { this.exitInspect(); return; }   // R toggles the overlay closed
         if (this._list == null || this._list.selectedIndex < 0) { return; }
         // FIS folders (all-collapsed): the selection can sit on a folder-header row, which maps to invIdx==-1.
         // Bail on an invalid item index so neither the inspect overlay nor the vanilla ExamineItem fallback ever
         // dispatches ExamineItem(-1) to the DLL -- a collapsed-header INSPECT is a clean no-op.
         if (this.invIdx(this._list.selectedIndex) < 0) { return; }
         // 0.0.60: ALL categories use the NATIVE ExamineItem (field feedback: the custom vector overlay showed
         // an emblem instead of the item). The engine opens its 3D examine view -- the REAL modded weapon/armor
         // model with the engine's own blurred backdrop -- which is exactly the requested behavior. The custom
         // overlay (enterInspect) is retired from this path but kept compiled for a future stats-compare mode.
         this.sfx("UIMenuOK");
         Theme.life("IV.ex" + this.invIdx(this._list.selectedIndex));
         BGSExternalInterface.call(this.codeObj, "ExamineItem", this.invIdx(this._list.selectedIndex));
      }
      // FIS folders: guard on the MAPPED item index (invIdx), not just selectedIndex>=0 -- an all-collapsed list
      // leaves the selection on a folder header (invIdx==-1), which would otherwise dispatch ItemDrop(-1,1) /
      // SetQuickkey(-1,0) to the DLL. Only act when the selection maps to a real InvItems row.
      private function doDrop():void
      {
         var di:int = this.invIdx(this._list.selectedIndex);
         Theme.life("IV.d" + di);   // 0.0.69: PRE-guard mark -- di==-1 (folder-header selection) shows up too
         if (di < 0) { return; }
         // 0.0.62: diagnostic -- log the selected item's count/favorite/equipped so a test reveals WHY the engine
         // rejects the drop (the index is proven correct: the same invIdx equips fine). Vanilla's direct DropItem
         // path always sends count 1; only its separate quantity dialog sends a larger count. Match the direct
         // contract here so both the R hotkey and context-menu DROP work without synthesizing that dialog.
         var row:Object = (this._lastData != null && this._lastData.InvItems != null && di < this._lastData.InvItems.length) ? this._lastData.InvItems[di] : null;
         var cnt:int = 1;
         var fav:int = (row != null && row.favorite != null) ? int(row.favorite) : -1;
         var eqp:* = (row != null && row.hasOwnProperty("equipState")) ? row.equipState : "?";
         var nm:String = (row != null && row.text != null) ? String(row.text) : "?";
         var listIdx:int = this._list.selectedIndex;
         // 0.0.65 DEDICATED DROP DIAGNOSTIC: the life-trail cap (700 chars) was eating the IV.dr marks, so write a
         // fresh string to root1.PipOS_droplog (DLL logs it immediately on change). Reveals listIdx vs invIdx vs
         // name/count/equipState so a test settles whether ItemDrop wants the display index or the InvItems index.
         var fidS:String = (row != null && row.formID != null) ? this.fidKey(row.formID) : "0";   // 0.0.69: canonical unsigned formID (feeds a future native-drop fallback)
         try { var rr:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null; if (rr != null) { rr.PipOS_droplog = (++this._dropSeq) + "|list=" + listIdx + "|inv=" + di + "|cnt=" + cnt + "|fav=" + fav + "|eq=" + eqp + "|fid=" + fidS + "|" + nm; } } catch (ed:*) {}
         this.sfx("UIMenuOK");
         BGSExternalInterface.call(this.codeObj, "ItemDrop", di, cnt);
      }
      private var _dropSeq:int = 0;
      private function doCycleDamage():void { this._dmgIndex++; this.sfx("UIMenuPrevNext"); this.renderCard(); }
      private function doFav():void     { if (this.invIdx(this._list.selectedIndex) >= 0) { this.sfx("UIPipBoyFavoriteMenuDPadA"); BGSExternalInterface.call(this.codeObj, "SetQuickkey", this.invIdx(this._list.selectedIndex), 0); } }
      // Z / L3 fallback: cycle our own per-category sort NAME(A-Z) -> WT(desc) -> VAL(desc) -> NAME ... (matches the
      // mockup's cycling "Sort" but authoritative in OUR list order, so it agrees with the clickable headers).
      private function doSort():void
      {
         var tab:int = this._curTab; if (tab < 0 || tab >= this._sortCol.length) { return; }
         var cur:int = int(this._sortCol[tab]);
         var next:int = (cur == 0) ? 2 : ((cur == 2) ? 3 : 0);
         this._sortCol[tab] = next; this._sortAsc[tab] = (next == 0);
         this.sfx("UIMenuPrevNext");
         if (this._lastData != null) { this.rebuildList(this._lastData); }
         this.updateInvTitle(); this.drawSortIndicator();
      }

      // QOL-1: click a column header to sort by it; click the active column again to flip asc/desc. NAME defaults
      // A-Z; numeric columns default high->low. Sort is per-category and preserves the selected item (rebuildList).
      private function onHeaderClick(e:MouseEvent):void
      {
         var col:int = int(String(e.currentTarget.name).substr(2));   // "hc<idx>"
         if (col == 1 && this._curTab != 0) { return; }               // opt (AMMO) column hidden off-weapons
         var tab:int = this._curTab; if (tab < 0 || tab >= this._sortCol.length) { return; }
         if (int(this._sortCol[tab]) == col) { this._sortAsc[tab] = !this._sortAsc[tab]; }
         else { this._sortCol[tab] = col; this._sortAsc[tab] = (col == 0); }
         this.sfx("UIMenuPrevNext");
         if (this._lastData != null) { this.rebuildList(this._lastData); }
         this.updateInvTitle(); this.drawSortIndicator();
      }

      // Filter + per-category sort + setItems + quick, preserving the selected item by its ORIGINAL InvItems index.
      // Pool-safe: no field creation or field-geometry writes (setItems/selectIndexSilent -> PipList.render, which
      // is update-only on the already-built pool).
      private function rebuildList(d:Pipboy_DataObj):void
      {
         if (d == null || this._list == null) { return; }
         var sameTab:Boolean = (this._builtTab == this._curTab);
         var prevOi:int = (sameTab && this._list.selectedIndex >= 0) ? this.invIdx(this._list.selectedIndex) : -1;
         if (this._builtTab >= 0) { this.persistListMem(); }
         var flt:int = int(d.InvFilter);
         var src:Array = d.InvItems;
         var pairs:Array = [];
         if (src != null) {
            for (var ii:int = 0; ii < src.length; ii++) {
               var it:Object = src[ii];
               if (it != null && (!it.hasOwnProperty("filterFlag") || (int(it.filterFlag) & flt) != 0)) { pairs.push({ it:it, oi:ii }); }
            }
         }
         this.applySort(pairs);
         // #6: a cross-category pending select must land on its item even if that item's folder is collapsed by
         // default -- open it BEFORE grouping so the item row is present in the grouped entries/_invMap.
         if (this._pendingFavFormID != null) { this.openFolderForFormID(this._pendingFavFormID); }
         // FIS FOLDERS: group the sorted pairs under folder headers when the category is tagged (else flat). The
         // returned entries interleave header markers ({__folder:true,...}) with InvItems rows; _invMap parallels
         // it (header -> -1). Sorting already ran on `pairs`, so items keep the active-column order WITHIN folders.
         var grp:Object = this.groupPairs(pairs);
         var shown:Array = grp.entries as Array; this._invMap = grp.map as Array;
         var newSel:int = 0;
         if (prevOi >= 0) { for (var m:int = 0; m < this._invMap.length; m++) { if (int(this._invMap[m]) == prevOi) { newSel = m; break; } } }
         this._list.setItems(shown, this.itemAdapter);
         if (sameTab) { this._list.selectIndexSilent(newSel); }
         else {
            var savedSel:int = (this._curTab >= 0 && this._curTab < this._listSelMem.length) ? int(this._listSelMem[this._curTab]) : 0;
            var savedTop:int = (this._curTab >= 0 && this._curTab < this._listTopMem.length) ? int(this._listTopMem[this._curTab]) : 0;
            this._list.restoreView(savedSel, savedTop);
         }
         this._builtTab = this._curTab; this.persistListMem();
         this.renderQuick();
         // A. QA cross-category select: a QA click on an item outside the current category stashed its formID and
         // switched tabs; now that this category's list is built, select it (fires onListSel -> card). No-op if the
         // item isn't here or is already the selection.
         if (this._pendingFavFormID != null) {
            var pdi:int = this.findDisplayIndexByFormID(this._pendingFavFormID);
            this._pendingFavFormID = null;
            if (pdi >= 0) { this._list.selectIndex(pdi); }
         }
         // TASK B: refresh the item card for the (preserved) selection -- selectIndexSilent does NOT fire
         // onListSel, so without this the card would keep showing the pre-refresh/pre-sort item.
         this._selRow = this.selRow(); this.renderCard();
      }

      // Sort the filtered {it,oi} pairs by the active category column. NAME + apparel SLOT sort as strings; the
      // other columns parse the numeric out of the displayed cell (via itemAdapter, so it matches on-screen values).
      private function applySort(pairs:Array):void
      {
         var tab:int = this._curTab; if (tab < 0 || tab >= this._sortCol.length) { return; }
         var col:int = int(this._sortCol[tab]); if (col < 0) { return; }
         var asc:Boolean = Boolean(this._sortAsc[tab]);
         var numeric:Boolean = (col != 0) && !(col == 1 && tab != 0);
         var self:PipOS_InvPage = this;
         pairs.sort(function(pa:Object, pb:Object):Number {
            // Primary compare on the active column, flipped by asc/desc.
            var primary:Number = 0;
            if (numeric) { var na:Number = self.sortNum(pa.it, col); var nb:Number = self.sortNum(pb.it, col); primary = (na < nb) ? -1 : ((na > nb) ? 1 : 0); }
            else { var sa:String = self.sortStr(pa.it, col); var sb:String = self.sortStr(pb.it, col); primary = (sa < sb) ? -1 : ((sa > sb) ? 1 : 0); }
            primary = asc ? primary : -primary;
            if (primary != 0) { return primary; }
            // 0.0.33 audit fix A4: NAME tiebreak is ALWAYS ascending A-Z (matches the mockup), independent of the
            // primary direction. The old code applied the asc/desc factor to the tiebreak too, so a descending
            // numeric sort came out reverse-alphabetical on ties.
            var xa:String = self.itemName(pa.it).toLowerCase(); var xb:String = self.itemName(pb.it).toLowerCase();
            return (xa < xb) ? -1 : ((xa > xb) ? 1 : 0);
         });
      }
      private function sortCols(it:Object):Array { var a:Object = this.itemAdapter(it); return (a != null && a.cols != null) ? (a.cols as Array) : ["", "", "", ""]; }
      private function sortStr(it:Object, col:int):String { var c:Array = this.sortCols(it); return (col < c.length && c[col] != null) ? String(c[col]).toLowerCase() : ""; }
      private function sortNum(it:Object, col:int):Number
      {
         var c:Array = this.sortCols(it); var s:String = (col < c.length && c[col] != null) ? String(c[col]) : "";
         var mm:Array = s.match(/-?\d+(?:\.\d+)?/g);
         if (mm == null || mm.length == 0) { return -1; }   // no number -> sorts to the low end
         return parseFloat(String(mm[mm.length - 1]));       // last numeric token ("5.56 (225)" -> 225)
      }
      private function itemName(it:Object):String { return (it != null && it.text != null) ? String(it.text) : ""; }

      // "INVENTORY . <CAT>[ . BY <KEY>]" -- update-only (setText on the pooled field).
      private function updateInvTitle():void
      {
         if (this._invTitle == null) { return; }
         var cat:String = (this._curTab >= 0 && this._curTab < CATS.length) ? String(CATS[this._curTab]) : "";
         var suf:String = ""; var tab:int = this._curTab;
         if (tab >= 0 && tab < this._sortCol.length) {
            var col:int = int(this._sortCol[tab]);
            if (col == 0) { suf = " · BY NAME"; }
            else if (col == 2) { suf = " · BY WEIGHT"; }
            else if (col == 3) { suf = " · BY VALUE"; }
            else if (col == 1) { suf = " · BY " + ((tab == 0) ? "AMMO" : "SLOT"); }
         }
         Theme.setText(this._invTitle, "INVENTORY · " + cat + suf);
      }

      // Draw the active-column sort caret (asc = up, desc = down) as vector graphics -- font-independent, no
      // geometry writes. Positioned beside the header label using the frozen column geometry + a label-length
      // estimate (never a runtime text-width read).
      private function drawSortIndicator():void
      {
         if (this._hdrMark == null || this._colGeom == null) { return; }
         var g:* = this._hdrMark.graphics; g.clear();
         var tab:int = this._curTab; if (tab < 0 || tab >= this._sortCol.length) { return; }
         var col:int = int(this._sortCol[tab]); if (col < 0 || col >= this._colGeom.length) { return; }
         if (col == 1 && tab != 0) { return; }   // opt column hidden off-weapons
         var asc:Boolean = Boolean(this._sortAsc[tab]);
         var geo:Object = this._colGeom[col];
         var lbl:String = (col < this._hdrLabels.length) ? String(this._hdrLabels[col]) : "";
         var lw:Number = lbl.length * 7;         // ~7px/char at 10px bold + letterspacing
         var cy:Number = (Theme.BY + 16) + 9;
         var cx:Number = (String(geo.align) == "right") ? (this._list.x + Number(geo.x) + Number(geo.w) - lw - 9) : (this._list.x + Number(geo.x) + lw + 6);
         Theme.caret(g, cx, cy, asc, Theme.PHOS_BRIGHT);
      }

      // QOL-4: expand/collapse the list. See the pool-sizing note on the fields; the whole reveal is a container
      // scrollRect + panel-Shape tween on a Ticker (time-based, honours the FO4 30fps root), never per-field geometry.
      private function onExpandBtn(e:MouseEvent):void { this.doExpand(); }
      private function doExpand():void
      {
         this._expanded = !this._expanded;
         this._expandDir = this._expanded ? 1 : -1;
         this.sfx("UIMenuPrevNext");
         if (this._expanded) {
            // Reveal the extra rows NOW (pool holds EXPANDED_ROWS, so render() only toggles visibility -- no field
            // creation/geometry). The panel + clip then GROW to uncover them; card content fades beneath.
            this._list.setRenderRows(EXPANDED_ROWS);
         }
         this.drawExpandGlyph();
         if (this._expandTicker == null) { this._expandTicker = new Ticker(this, this.onExpandTick); }
         this._expandTicker.start();
      }
      private function onExpandTick(dt:Number):void
      {
         this._expandT += (dt / 0.25) * this._expandDir;   // ~0.25s, time-based
         if (this._expandT < 0) { this._expandT = 0; }
         if (this._expandT > 1) { this._expandT = 1; }
         var e:Number = this._expandT * this._expandT * (3 - 2 * this._expandT);   // smoothstep
         // Keep the item card present as context while the list expands, but de-emphasize it to 25%.
         // Sprite alpha is graphics-only and safe on the tick path; collapse restores it along the same tween.
         this._card.alpha = 1.0 - 0.75 * e;
         this._cardBg.alpha = this._card.alpha;
         var h:Number = this._listH + (this._expH - this._listH) * e;
         this.drawListBg(h);
         var clip:Number = h - 44; var maxClip:Number = EXPANDED_ROWS * 25;
         if (clip > maxClip) { clip = maxClip; }
         this._list.setClipHeight(clip);
         if (this._expandDir > 0 && this._expandT >= 1) {
            this._expandTicker.stop(); this._list.setClipHeight(EXPANDED_ROWS * 25);
         } else if (this._expandDir < 0 && this._expandT <= 0) {
            this._expandTicker.stop(); this._list.setClipHeight(COLLAPSED_ROWS * 25); this._list.setRenderRows(COLLAPSED_ROWS); this._card.alpha = 1.0; this._cardBg.alpha = 1.0;
         }
      }

      private function onPageStage(e:Event):void
      {
         this.ensureText(); if (this._dbg != null) this._dbg.mark("add");
         this.publishInventoryPage(true);
         if (stage != null) {
            stage.addEventListener(KeyboardEvent.KEY_DOWN, this.onKey);
            stage.addEventListener(MouseEvent.MOUSE_MOVE, this.onMouseMove);   // B: tooltip cursor-follow
            stage.addEventListener(MouseEvent.MOUSE_WHEEL, this.onInspectWheel);   // inspect emblem zoom (acts only while inspecting)
            // P0-B page-mouse diagnostic (0.0.25) RETIRED in 0.0.27: the Loader-transparency fix in
            // Chrome.onAdded is field-confirmed (sub-tabs/list rows/hover all clickable), so the capture-phase
            // stage/page MOUSE_DOWN loggers + logAncestors have served their purpose and are removed.
         }
         // 0.0.59 LIVE-3D SWAP: the DLL's PipOS_char3d contract flips available:true ~35ms AFTER this page is
         // built (log-proven ordering), so a build-time check always misses it. Poll every frame (two dynamic
         // member reads + at most one visibility write -- crash-law-safe) and swap Vault Boy <-> the 3D window.
         if (this._charPoll == null) { this._charPoll = new Ticker(this, this.onCharPoll); }
         this._charPoll.start();
      }
      // Reserve the figure slot as soon as Live 3D is active. Waiting for available:true exposes Vault Boy during
      // the model-placement/display-attach frames on every Inventory transition. Availability now controls only
      // the readiness caption; a brief empty slot is preferable to flashing the wrong figure.
      private var _charPoll:Ticker;
      private var _char3dOn:Boolean = false;
      private var _char3dReady:Boolean = false;
      private var _pageSignalRoot:* = null;
      private var _eqPollN:int = 0;
      // The native renderer cannot reliably read PipboyMenu.DataObj through this shell. Publish the actual page
      // lifecycle on root1 instead: ADDED means Inventory is installed, REMOVED means it is no longer visible.
      private function publishInventoryPage(active:Boolean):void
      {
         try {
            if (active && stage != null && stage.numChildren > 0) { this._pageSignalRoot = stage.getChildAt(0); }
            if (this._pageSignalRoot != null) { this._pageSignalRoot.PipOS_inventoryPageActive = active; }
         } catch (ep:*) {}
      }
      private function onCharPoll(dt:Number):void
      {
         var active:Boolean = false;
         var ready:Boolean = false;
         try {
            var rr:* = (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null;
            var c3:* = (rr != null) ? rr.PipOS_char3d : null;
            active = (c3 != null && c3.active == true);
            ready = (active && c3.available == true);
         } catch (e3:*) { active = false; ready = false; }
         if (active != this._char3dOn) {
            this._char3dOn = active;
            if (this._vb != null) { this._vb.visible = !active; }
         }
         if (ready != this._char3dReady) {
            this._char3dReady = ready;
            if (this._charCap != null) { Theme.setText(this._charCap, ready ? "LIVE CAPTURE" : ""); }
            Theme.life(ready ? "IV.3d1" : "IV.3d0");
         }
         // 0.0.60: equipment live-refresh. The DLL re-pushes root1.PipOS_equip ~2x/s while the menu is open;
         // re-apply every ~15 frames (applyEquip is diff-only, so unchanged pushes cost 10 string compares).
         if (++this._eqPollN >= 15) { this._eqPollN = 0; this.applyEquip(); }
         this.tickEquipPulse(dt);
         // 0.0.62 DLL-FORWARDED RIGHT-CLICK: GFx never delivered RIGHT_MOUSE_DOWN (0.0.61 log: IV.rc=0), so the
         // DLL polls the right button and bumps root1.PipOS_rclickN on each press. Open the context menu at the
         // row currently under the cursor (PipList tracks the hover). No coords come from the DLL -- we use the
         // page's own live mouse position, converted to stage coords for onRowContext.
         try {
            var rn:* = (this._rrPoll != null) ? this._rrPoll.PipOS_rclickN : null;
            if (rn != null) {
               var rv:int = int(rn);
               if (rv != this._rclickLast) {
                  this._rclickLast = rv;
                  Theme.life("IV.rc");
                  // 0.0.69: POSITION-based row targeting (rowAtMouse), not hoverIndex -- GFx never re-fires
                  // ROLL_OVER when the menu closes under a stationary cursor, so hover went stale and the menu
                  // "broke" after one use. A right-click with the menu already open RE-TARGETS to the row under
                  // the cursor (close+reopen) instead of just closing.
                  var hi:int = (this._list != null) ? this._list.rowAtMouse() : -1;
                  if (hi >= 0) {
                     this.closeContextMenu();
                     var ent:Object = this._list.entryAt(hi);
                     var gp:Point = this.localToGlobal(new Point(this.mouseX, this.mouseY));
                     this.onRowContext(hi, ent, gp.x, gp.y);
                  } else { this.closeContextMenu(); }
               }
            }
         } catch (erc:*) {}
      }
      private var _rclickLast:int = 0;
      private function get _rrPoll():* { try { return (stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null; } catch (e:*) { return null; } }
      private function onPageUnstage(e:Event):void
      {
         this.publishInventoryPage(false);
         if (stage != null) {
            stage.removeEventListener(KeyboardEvent.KEY_DOWN, this.onKey);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE, this.onMouseMove);
            stage.removeEventListener(MouseEvent.MOUSE_WHEEL, this.onInspectWheel);
         }
         // TEARDOWN: ENTER_FRAME broadcasts fire even off-stage, so a settled inspect (badge pulse) or an
         // in-flight expand would tick forever after the page is removed. Stop both tickers and force the inspect
         // overlay fully CLOSED + state reset so re-opening the Pip-Boy starts clean (never a stale overlay).
         if (this._insTicker != null) { this._insTicker.stop(); }
         if (this._expandTicker != null) { this._expandTicker.stop(); }
         if (this._charPoll != null) { this._charPoll.stop(); }   // 0.0.59: 3D-contract poll dies with the page
         this.closeContextMenu();   // 0.0.61: drop any open context menu + its stage listener on teardown
         this._inspecting = false; this._insFadeDir = 0; this._insFade = 0;
         if (this._insLay != null) { this._insLay.visible = false; this._insLay.alpha = 0; }
      }

      private function onKey(e:KeyboardEvent):void {
         if (this._dbg != null) {
            this._dbg.input("key", e.keyCode, e.target);
            if (this._dbg.isDumpKey(e.keyCode)) {
               this._dbg.clearDump(); this._dbg.toggleDump();
               if (this._lastData != null) {
                  // Dump the SELECTED item (mapped through the display->InvItems index machinery), not [0].
                  var selI:int = (this._list != null) ? this._list.selectedIndex : -1;
                  var oiSel:int = this.invIdx(selI);
                  this._dbg.dump("InvItems[selected] (G4 fields)", (this._lastData.InvItems != null && oiSel >= 0 && oiSel < this._lastData.InvItems.length) ? this._lastData.InvItems[oiSel] : null);
                  this._dbg.dump("selected list index / invIdx", selI + " / " + oiSel);
                  this._dbg.dump("InvFilter", this._lastData.InvFilter);
                  this._dbg.dump("FavoritesList[0] (G3)", (this._lastData.FavoritesList != null && this._lastData.FavoritesList.length > 0) ? this._lastData.FavoritesList[0] : null);
               }
               // P0 (0.0.27): dump the engine-filled _cardInfo so a backtick screenshot after selecting an item
               // settles data-vs-render if the direct renderCard() still shows an empty card. [0].text = title;
               // later entries carry .text/.value pairs + .showAsDescription. length + one later entry included.
               {
                  this._dbg.dump("_cardInfo.length", (this._cardInfo != null) ? this._cardInfo.length : 0);
                  this._dbg.dump("_cardInfo[0] (title)", (this._cardInfo != null && this._cardInfo.length > 0) ? this._cardInfo[0] : null);
                  this._dbg.dump("_cardInfo[1] (pair sample)", (this._cardInfo != null && this._cardInfo.length > 1) ? this._cardInfo[1] : null);
               }
               return;
            }
         }
         // 0.0.61: while the context menu is open it captures keys -- Escape closes it, everything else is swallowed.
         if (this._ctxOpen) { if (e.keyCode == 27) { this.closeContextMenu(); } return; }
         // While inspecting, the overlay CAPTURES W/S/R/Escape and the underlying list does NOT act on any key.
         if (this._inspecting) { this.onInspectKey(e.keyCode); return; }
         if (e.keyCode == 69) { this.doExpand(); return; }   // E = expand/collapse the inventory list (QOL-4 hotkey)
         if (e.keyCode == 82) { Theme.life("IV.rK"); this.doDrop(); return; }   // 0.0.60: R = DROP claimed directly; 0.0.69: mark PROVES the key reaches this branch
         this._list.handleKey(e.keyCode);
      }

      // Inspect-mode key capture (W prev / S next / Escape exit); every other key is swallowed so the list stays
      // inert. R is DELIBERATELY NOT handled here: keyboard R already routes through the engine PCKey ->
      // ProcessUserEvent("R3") -> doInspect toggle, the single owner of R. Handling R here TOO made exit order-
      // dependent (onKey clearing _inspecting before doInspect re-entered enterInspect == reopen). Escape has no
      // ProcessUserEvent binding, so it stays here. No field/geometry access.
      private function onInspectKey(keyCode:int):void
      {
         if (keyCode == 87) { this.cycleInspect(-1); }        // W = PREV
         else if (keyCode == 83) { this.cycleInspect(1); }    // S = NEXT
         else if (keyCode == 27) { this.exitInspect(); }      // Escape = EXIT
      }

      override public function ProcessUserEvent(param1:String, param2:Boolean):Boolean
      {
         if (!param2)
         {
            switch (param1)
            {
               case "Accept":    this._list.pressSelected(); return true;
               case "XButton":   this.doDrop();        return true;
               case "R3":        this.doInspect();     return true;
               case "L3":        this.doSort();        return true;
               case "RShoulder": this.doFav();         return true;
               case "LShoulder": this.doCycleDamage(); return true;
            }
         }
         return false;
      }
   }
}
