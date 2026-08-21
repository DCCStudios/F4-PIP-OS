package pipos
{
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.events.Event;
   import pipos.Ticker;
   import flash.text.TextField;
   import flash.text.TextFormat;

   // Reusable PIP-OS phosphor scrolling list. Replaces the vanilla BSScrollingList presentation while
   // keeping the same selection/press event flow. Rows are POOLED TextFields + Shapes.
   // Adapter(entry) -> { label:String, right:String, star:Boolean, legendary:Boolean, dim:Boolean, cols:Array }.
   //
   // ============================================================================================
   // CRASH-STRUCTURAL POOLING (0.0.31). CORRECTED DIAGNOSIS (supersedes the 0.0.29/0.0.30 auto-size +
   // unicodeRange theories in the comments this file used to carry):
   //   The FindFont(NULL) CTD (Fallout4.exe+2285D26, rcx=0) is a SCRIPT GEOMETRY-WRITE on a FRESH / EMPTY /
   //   just-attached TextField executed INSIDE interaction dispatch (a mouse-click GenerateMouseEvents, or
   //   the data-change the engine pushes SYNCHRONOUSLY inside that click). The write (`.width =` == the
   //   ThunkFunc property-setter -> TextField::SetWidth -> GetViewRect -> Format -> FindFont(NULL)) reformats
   //   the field before its font handle is resolved and takes the access violation. It is GLYPH-INDEPENDENT:
   //   the crashing field was one of render()'s fresh EMPTY cells receiving `.width` BEFORE any text was set,
   //   so Theme.sanitize (which fixed the OLDER texted-glyph class) is necessary but not sufficient.
   //   The STRUCTURAL fix is here: build every row field ONCE, in the proven-safe build window (the first
   //   render, which runs on the page's first data event while on stage), then NEVER create a field or write
   //   .width/.height/.x/.y/.autoSize on any interaction-reachable path. render() is UPDATE-ONLY thereafter:
   //   setText / textColor / visible / scrollRect / filters / defaultTextFormat / graphics redraw only.
   // ============================================================================================
   public class PipList extends Sprite
   {
      public var onSelectionChange:Function;   // function(index:int)
      public var onItemPress:Function;         // function(index:int)
      public var playSound:Function;           // function(event:String)
      // 0.0.34: hover callback for the page tooltip. Fired with the hovered ENTRY index on roll-over and -1 on
      // roll-out. ADDITIVE + null-guarded: pages that don't assign it are behaviourally identical (no fields,
      // no geometry -- a pure callback invocation, so onRowOver/onRowOut stay update-only and pool-safe).
      public var onHover:Function;             // function(index:int)  (index == -1 on roll-out)
      // Folder grouping (FallUI/FIS tag folders): fired when a CLICKABLE separator (a folder header) is clicked,
      // with the header ENTRY object. ADDITIVE + null-guarded -- a page that never assigns it keeps plain,
      // non-clickable separators (DATA/RADIO). Pure callback: onRowClick stays create-free + geometry-free.
      public var onFolderToggle:Function;      // function(entry:Object)
      // 0.0.61: right-click context callback. Fired on a row's RIGHT_MOUSE_DOWN with (displayIdx, entry, stageX,
      // stageY). ADDITIVE + null-guarded -- a page that never assigns it is behaviourally identical. Pure callback
      // (no fields/geometry), so it stays pool-safe. NOTE: whether GFx delivers right-mouse to the movie at all is
      // runtime-unproven here; the page logs a breadcrumb when this fires so a test decides it.
      public var onRowContext:Function;        // function(idx:int, entry:Object, ex:Number, ey:Number)
      public var onViewportChange:Function;    // function(sel:int, top:int), used to persist list position
      public var columns:Array = null;         // optional [{w,align}]; adapter returns cols:[String,...]. STABLE by pool-build time.
      public var optCol:int = -1;              // index of an OPTIONAL column (e.g. INV AMMO); toggled by optOn without geometry writes
      public var optOn:Boolean = true;         // when false the opt column is hidden and the NAME cell widens (scrollRect only)

      private static const MARK_STEP:int = 18; // px reserved per favorite/legendary marker in the LABEL-branch gutter
      // Mockup .row padding is 0 12px -> names start ~12px from the panel edge. NAME_X is the name-cell left edge
      // for BOTH branches (was 10+MARK_STEP=28 for cols, a too-wide marker gutter). The legendary sparkle now
      // draws INSIDE this small left padding (slightly preceding the name); the favorite star still TRAILS the name.
      private static const NAME_X:Number = 12;
      // Mockup .row font-size 13 -> Theme.fs(13)=10 local; letter-spacing .02em (~0) -> ROW fields use near-zero
      // spacing (Theme.tf's base 0.5 is kept only on structural labels/headers/tabs, which are built elsewhere).
      private static const ROW_FS:int = 13;
      private static const ROW_LS:Number = 0.1;

      private var _w:Number;
      private var _rowH:Number;
      private var _visible:int;                // rows currently RENDERED (collapsed vs expanded window)
      private var _poolRows:int;               // rows the pool was BUILT for (>= max _visible ever needs) -- so
                                               // an expand never creates a field on the interaction path
      private var _fill:Sprite;                // P1 (0.0.42): ALL rect FILLS (selection bar, alt-row stripe, folder band, scroll bar, dividers) draw here, BELOW the row text
      private var _rows:Sprite;
      private var _markers:Sprite;             // P1-C: favorite/legendary glyphs + selection brackets + folder caret on their OWN layer (never share a pen path with _rows/_fill)
      private var _hoverLayer:Sprite;
      private var _hoverIdx:int = -1;
      private var _selMarqField:TextField = null;    // selected row's NAME field (default marquee target)
      private var _hoverMarqField:TextField = null;  // hovered row's NAME field (priority while hovering)
      private var _nameByIdx:Object = {};            // idx -> NAME field, rebuilt each render (visible rows only)
      private var _marqT:Number = 0; private var _marqTicker:Ticker;
      // 0.0.43 SELECTION PULSE (mockup .row.sel glow, ref lgdpulse box-shadow). A subtle phosphor glow ring is
      // redrawn around the selected row every marquee tick at an OSCILLATING alpha, so the selection "breathes".
      // GRAPHICS/ALPHA ONLY -- its own mouse-transparent Sprite layer, redrawn from a time-based Number; no
      // TextField access, so it is crash-law-legal and rides the existing 30fps-safe marquee Ticker.
      private var _selGlow:Sprite;             // dedicated glow layer (topmost, mouse-transparent)
      private var _pulseT:Number = 0;          // pulse phase (seconds); advanced by onMarqTick
      private var _selGlowY:Number = 0;        // selected row's on-screen top (list-local), captured in render()
      private var _selShown:Boolean = false;   // is a selected row currently inside the visible window?
      private var _entries:Array = [];
      private var _adapter:Function;
      private var _sel:int = -1;
      private var _top:int = 0;

      // Pool (built ONCE, lazily, on the first on-stage render). One slot per visible row.
      // Each slot = { hit:Sprite, sep:TextField, cols:Array<TextField> | null, lbl:TextField, rt:TextField }.
      private var _pool:Array = [];
      private var _pooled:Boolean = false;
      private var _markX:Number = 10;          // NAME/label left edge (columns branch reserves a fixed marker gutter)
      private var _nameNarrowVis:Number = 0;   // NAME visible width with the opt column present  (opt-on)
      private var _nameWideVis:Number = 0;     // NAME visible width with the opt column hidden    (opt-off)

      // maxRows sizes the POOL (default = visibleRows). Pass a larger maxRows to reserve extra rows the
      // expand feature reveals; the pool is built for maxRows up front so revealing rows is pure visibility.
      public function PipList(width:Number, rowHeight:Number = 26, visibleRows:int = 12, maxRows:int = 0)
      {
         super();
         this._w = width; this._rowH = rowHeight; this._visible = visibleRows;
         this._poolRows = (maxRows > visibleRows) ? maxRows : visibleRows;
         // P1 (0.0.42): FILL layer FIRST (bottom) so every rect fill (selection bar, alt-row stripe, folder band,
         // scroll bar) renders BELOW the pooled row text. All fills are self-contained drawRect/drawRoundRect (each
         // self-moves the pen), so this pen never carries a manual moveTo/lineTo path that could bleed to the corner.
         this._fill = new Sprite(); this._fill.mouseEnabled = false; this._fill.mouseChildren = false; addChild(this._fill);
         this._rows = new Sprite();
         addChild(this._rows);
         this._hoverLayer = new Sprite(); this._hoverLayer.mouseEnabled = false; this._hoverLayer.mouseChildren = false; addChild(this._hoverLayer);
         // P1-C: markers (favorite star / legendary sparkle / selection brackets / folder caret) draw onto a
         // DEDICATED Sprite, never the shared _rows/_fill pen. Every one of those is a MANUAL moveTo/lineTo path;
         // on the shared full-panel pen (spanning from the origin) GFx bled the stroke onto other rows + a diagonal
         // to the corner (the "star-line" class). Isolated here, topmost + mouse-transparent, every op begins with a
         // lineStyle() reset so no path can connect to the panel corner.
         this._markers = new Sprite(); this._markers.mouseEnabled = false; this._markers.mouseChildren = false; addChild(this._markers);
         // 0.0.43 selection-pulse glow: TOPMOST + mouse-transparent. Only a thin perimeter ring is drawn here at a
         // pulsing alpha, so it never obscures the (inset) row text. Its own layer -> its per-tick clear/redraw
         // never disturbs the fill/marker/row pens.
         this._selGlow = new Sprite(); this._selGlow.mouseEnabled = false; this._selGlow.mouseChildren = false; addChild(this._selGlow);
         // Clip backstop: rows/labels/values can never render outside the list box even if a value is long.
         this.scrollRect = new Rectangle(0, 0, this._w, this._rowH * this._visible);
         addEventListener(MouseEvent.MOUSE_WHEEL, this.onWheel);
         addEventListener(Event.ADDED_TO_STAGE, this.onListStage);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onListUnstage);
      }

      private function onListStage(e:Event):void { if (this._marqTicker == null) { this._marqTicker = new Ticker(this, this.onMarqTick); } this._marqTicker.start(); }
      private function onListUnstage(e:Event):void { if (this._marqTicker != null) { this._marqTicker.stop(); } }

      // P1-C marquee: the NAME cell is a wide (4000px) pooled field clipped by an external scrollRect viewport.
      // Sliding scrollRect.x moves that viewport, revealing glyphs past the column edge. scrollRect + .textWidth
      // reads are SetWidth-free; no field creation; time-based (Ticker); on-stage. Target = hovered row if any,
      // else the selected row.
      private function onMarqTick(dt:Number):void
      {
         // 0.0.43 SELECTION PULSE (runs first, unconditionally): advance the phase + redraw the glow at an
         // oscillating alpha. Graphics/alpha only (no TextField access) -> crash-law-legal; period ~2.1s to match
         // the mockup's .row.sel glow cadence, honouring the 30fps root via the time-based dt.
         this._pulseT += dt;
         this.drawSelGlow();
         var f:TextField = (this._hoverMarqField != null) ? this._hoverMarqField : this._selMarqField;
         if (f == null) { return; }
         var rect:Rectangle = f.scrollRect; if (rect == null) { return; }
         var over:Number = f.textWidth - rect.width + 4;   // px of glyphs clipped past the column box
         if (over <= 0) { if (rect.x != 0) { rect.x = 0; f.scrollRect = rect; } return; }
         this._marqT += dt;
         if (this._marqT < 1.5) { if (rect.x != 0) { rect.x = 0; f.scrollRect = rect; } return; }   // ~1.5s dwell
         var cycle:Number = over * 2 + 1;
         var pos:Number = ((this._marqT - 1.5) * 60) % cycle;   // ~60 px/s ping-pong
         rect.x = (pos <= over) ? pos : (cycle - pos);
         f.scrollRect = rect;
      }

      // 0.0.43 selection-pulse redraw (graphics/alpha ONLY; no field access, no geometry write). Clears the glow
      // layer and, when a selected row is inside the visible window, strokes a soft phosphor ring around it at an
      // alpha that oscillates on _pulseT. Two concentric outlines (outer faint bloom + inner brighter edge) read
      // as a subtle box-shadow-style breathe over the green selection bar without touching the inset row text.
      private function drawSelGlow():void
      {
         var g:* = this._selGlow.graphics; g.clear();
         if (!this._selShown) { return; }
         var y:Number = this._selGlowY;
         var k:Number = 0.5 + 0.5 * Math.sin(this._pulseT * 3.0);   // 0..1, period ~2.09s
         var inner:Number = 0.22 + 0.40 * k;                         // 0.22 .. 0.62 bright edge
         var outer:Number = 0.06 + 0.16 * k;                         // 0.06 .. 0.22 faint bloom
         Theme.frameRect(g, -1.5, y - 1.5, this._w + 3, this._rowH + 1, Theme.PHOS_BRIGHT, outer, 2.5);
         Theme.frameRect(g, 0.5, y + 0.5, this._w - 1, this._rowH - 3, Theme.PHOS_BRIGHT, inner, 1);
      }

      public function get selectedIndex():int { return this._sel; }
      public function get topIndex():int { return this._top; }
      public function get length():int { return this._entries ? this._entries.length : 0; }
      public function get hoverIndex():int { return this._hoverIdx; }   // 0.0.62: DLL-forwarded right-click asks which row the cursor is on
      public function entryAt(i:int):Object { return (i >= 0 && i < this._entries.length) ? this._entries[i] : null; }
      // 0.0.69: POSITION-based row hit-test for the context menu. hoverIndex depends on ROLL_OVER events, which
      // GFx does not re-fire when the context menu closes under a stationary cursor -- so the second right-click
      // on the same spot saw hoverIndex==-1 and the menu "broke until highlighting another item". Pure math on
      // the live mouse position instead; no event dependency.
      public function rowAtMouse():int
      {
         var lx:Number = this.mouseX, ly:Number = this.mouseY;
         if (lx < 0 || lx > this._w || ly < 0) { return -1; }
         var r:int = int(Math.floor(ly / this._rowH));
         if (r < 0 || r >= this._visible) { return -1; }
         var idx:int = this._top + r;
         return (idx >= 0 && idx < this._entries.length) ? idx : -1;
      }

      public function setItems(entries:Array, adapter:Function):void
      {
         this._entries = entries ? entries : [];
         this._adapter = adapter;
         if (this._sel >= this._entries.length) { this._sel = this._entries.length - 1; }
         if (this._sel < 0 && this._entries.length > 0) { this._sel = 0; }
         if (!this.isSelectable(this._sel)) { this._sel = this.nextSelectable(this._sel, 1); }
         this.clampScroll();
         this.render();
      }

      private function isSelectable(i:int):Boolean
      {
         if (i < 0 || i >= this._entries.length || this._adapter == null) { return i >= 0 && i < this._entries.length; }
         var a:Object = this._adapter(this._entries[i]);
         return !(a != null && a.separator == true);
      }
      private function nextSelectable(from:int, dir:int):int
      {
         var i:int = from;
         while (i >= 0 && i < this._entries.length) { if (this.isSelectable(i)) { return i; } i += dir; }
         return this._sel;
      }

      public function selectIndex(i:int, fireSound:Boolean = true):void
      {
         if (i < 0 || i >= this._entries.length || i == this._sel) { return; }
         if (!this.isSelectable(i)) { i = this.nextSelectable(i, i > this._sel ? 1 : -1); if (i == this._sel) { return; } }
         this._sel = i;
         this.clampScroll();
         this.render();
         if (fireSound && playSound != null) { playSound("UIGeneralFocus"); }
         if (onSelectionChange != null) { onSelectionChange(this._sel); }
      }

      // Select WITHOUT firing onSelectionChange/sound (used to preserve the selected item across a re-sort or
      // a data refresh). Pool-safe: only clampScroll + render (update-only) run.
      public function selectIndexSilent(i:int):void
      {
         if (i < 0 || i >= this._entries.length) { return; }
         if (!this.isSelectable(i)) { i = this.nextSelectable(i, 1); }
         this._sel = i; this.clampScroll(); this.render();
      }

      // Restore a previously saved selection + scroll window in one update-only operation. The saved top is
      // authoritative when it still contains the selection; otherwise clampScroll brings the selection onscreen.
      public function restoreView(i:int, top:int):void
      {
         if (this._entries.length == 0) { this._sel = -1; this._top = 0; this.render(); return; }
         if (i < 0) { i = 0; } if (i >= this._entries.length) { i = this._entries.length - 1; }
         if (!this.isSelectable(i)) {
            var probe:int = i;
            while (probe < this._entries.length && !this.isSelectable(probe)) { probe++; }
            if (probe >= this._entries.length) {
               probe = i - 1; while (probe >= 0 && !this.isSelectable(probe)) { probe--; }
            }
            i = (probe >= 0 && probe < this._entries.length) ? probe : 0;
         }
         this._sel = i;
         var maxTop:int = Math.max(0, this._entries.length - this._visible);
         this._top = Math.max(0, Math.min(top, maxTop));
         if (this._sel < this._top || this._sel >= this._top + this._visible) { this.clampScroll(); }
         this.render();
      }

      // Per-column geometry in list-LOCAL coords, matching buildPool's layout EXACTLY. Callable BEFORE the pool
      // is built so the page can align its header cells over the data columns (parity fix C1). Column x's are
      // stable regardless of optOn (the name field always advances by its narrow width; the opt column just hides).
      public function columnGeom():Array
      {
         if (this.columns == null) { return null; }
         var markX:Number = NAME_X;
         var fixedAll:Number = 0; var ci:int;
         for (ci = 0; ci < this.columns.length; ci++) { var cwv:Number = this.columns[ci].w; if (cwv > 0) { fixedAll += cwv; } }
         var nameNarrow:Number = this._w - markX - fixedAll - 10; if (nameNarrow < 20) { nameNarrow = 20; }
         var out:Array = []; var cx:Number = markX;
         for (ci = 0; ci < this.columns.length; ci++) {
            var col:Object = this.columns[ci]; var isName:Boolean = (ci == 0);
            var w:Number = isName ? nameNarrow : Number(col.w);
            out.push({ x:cx, w:w, align:(col.align != null ? String(col.align) : "left") });
            cx += w;
         }
         return out;
      }

      // Expand support (pool-safe): change how many pooled rows RENDER. Pool already holds _poolRows fields, so
      // this only toggles visibility/text via render() -- never creates a field or writes field geometry.
      public function setRenderRows(n:int):void
      {
         if (n > this._poolRows) { n = this._poolRows; }
         if (n < 1) { n = 1; }
         this._visible = n; this.clampScroll(); this.render();
      }
      // Grow/shrink the outer CLIP (this Sprite's scrollRect) for the reveal animation. scrollRect on a container
      // is explicitly exempt from the geometry-write rule (it is not a TextField geometry write).
      public function setClipHeight(hpx:Number):void
      {
         if (hpx < this._rowH) { hpx = this._rowH; }
         this.scrollRect = new Rectangle(0, 0, this._w, hpx);
      }

      // Returns true if the key was consumed. Only NAVIGATION lives here (up/down); activation
      // (Enter/A) is driven by each page's ProcessUserEvent "Accept" (single path).
      public function handleKey(code:uint):Boolean
      {
         if (code == 38) { this.selectIndex(this._sel - 1); return true; }   // up
         if (code == 40) { this.selectIndex(this._sel + 1); return true; }   // down
         return false;
      }

      public function pressSelected():void
      {
         if (this.isSelectable(this._sel) && onItemPress != null) { onItemPress(this._sel); if (playSound != null) { playSound("UIMenuOK"); } }
      }

      private function clampScroll():void
      {
         if (this._sel < this._top) { this._top = this._sel; }
         if (this._sel >= this._top + this._visible) { this._top = this._sel - this._visible + 1; }
         if (this._top < 0) { this._top = 0; }
      }

      private function onWheel(e:MouseEvent):void
      {
         var oldTop:int = this._top;
         this._top -= (e.delta > 0 ? 1 : -1);
         var maxTop:int = Math.max(0, this._entries.length - this._visible);
         if (this._top < 0) { this._top = 0; }
         if (this._top > maxTop) { this._top = maxTop; }
         this.render();
         if (this._top != oldTop && onViewportChange != null) { onViewportChange(this._sel, this._top); }
      }

      private function onRowClick(e:MouseEvent):void
      {
         var idx:int = int(String(e.currentTarget.name).substr(1));
         if (idx < 0 || idx >= this._entries.length) { return; }
         // Folder-header rows are clickable separators: toggle collapse via the page callback, never select.
         if (this._adapter != null) {
            var a:Object = this._adapter(this._entries[idx]);
            if (a != null && a.separator == true) {
               if (a.folder == true && onFolderToggle != null) { onFolderToggle(this._entries[idx]); }
               return;
            }
         }
         if (!this.isSelectable(idx)) { return; }
         this.selectIndex(idx, false);                 // select (fires onSelectionChange)
         if (onItemPress != null) { onItemPress(idx); } // W6: activate on the SAME click
         if (playSound != null) { playSound("UIMenuOK"); }
      }

      // 0.0.61: right-click on a row -> page context callback (display index + entry + stage coords). Selection
      // and folder/item routing are the page's job; this only forwards. Guarded, create-free, geometry-free.
      private function onRowRightClick(e:MouseEvent):void
      {
         var idx:int = int(String(e.currentTarget.name).substr(1));
         if (idx < 0 || idx >= this._entries.length) { return; }
         if (onRowContext != null) { onRowContext(idx, this._entries[idx], e.stageX, e.stageY); }
      }

      private function onRowOver(e:MouseEvent):void
      {
         var idx:int = int(String(e.currentTarget.name).substr(1));
         this._hoverIdx = idx; this.drawHover();
         var nf:TextField = this._nameByIdx[idx] as TextField;
         if (nf != null && nf.scrollRect != null && nf.textWidth > nf.scrollRect.width) {
            if (this._selMarqField != null && this._selMarqField != nf) {
               var sr:Rectangle = this._selMarqField.scrollRect;
               if (sr != null && sr.x != 0) { sr.x = 0; this._selMarqField.scrollRect = sr; }
            }
            this._hoverMarqField = nf; this._marqT = 0;
         }
         // 0.0.34: notify the page (tooltip). Pure callback -- no field/geometry work here.
         if (onHover != null) { onHover(idx); }
      }
      private function onRowOut(e:MouseEvent):void
      {
         this._hoverIdx = -1; this.drawHover();
         if (this._hoverMarqField != null) {
            var r:Rectangle = this._hoverMarqField.scrollRect;
            if (r != null && r.x != 0) { r.x = 0; this._hoverMarqField.scrollRect = r; }
            this._hoverMarqField = null;
         }
         this._marqT = 0;
         if (onHover != null) { onHover(-1); }
      }
      private function drawHover():void
      {
         var g:* = this._hoverLayer.graphics; g.clear();
         if (this._hoverIdx < this._top || this._hoverIdx >= this._top + this._visible || this._hoverIdx == this._sel) { return; }
         var y:Number = (this._hoverIdx - this._top) * this._rowH;
         g.beginFill(Theme.PHOS, 0.10); g.drawRoundRect(0, y, this._w, this._rowH - 2, 4, 4); g.endFill();
      }

      // ---- POOL BUILD (ONCE, on the first on-stage render = the page's first data event = proven-safe) ----
      // Every field a slot could ever need is created here, hidden and empty, with ALL geometry (x/y/width/
      // height/autoSize/scrollRect) baked in. render() only toggles visibility, sets text/color, redraws
      // graphics, and slides scrollRect.x for the marquee. No field creation or geometry write ever runs on an
      // interaction-reachable path again.
      private function buildPool():void
      {
         this._pooled = true;
         var isCols:Boolean = (this.columns != null);
         // Columns branch reserves ONE leading marker slot (the legendary sparkle leads the name; the favorite
         // star now TRAILS at the name column's right edge -- parity fix C2 -- so only one leading gutter is needed).
         this._markX = NAME_X;
         var rightReserve:Number = 96;
         var labelW:Number = this._w - this._markX - rightReserve - 8; if (labelW < 20) { labelW = 20; }
         var ci:int;
         if (isCols) {
            var fixedAll:Number = 0, fixedNoOpt:Number = 0;
            for (ci = 0; ci < this.columns.length; ci++) {
               var cwv:Number = this.columns[ci].w;
               if (cwv > 0) { fixedAll += cwv; if (ci != this.optCol) { fixedNoOpt += cwv; } }
            }
            this._nameNarrowVis = this._w - this._markX - fixedAll - 10; if (this._nameNarrowVis < 20) { this._nameNarrowVis = 20; }
            this._nameWideVis = this._w - this._markX - fixedNoOpt - 10; if (this._nameWideVis < 20) { this._nameWideVis = 20; }
         }
         var sepW:Number = Math.min(this._w - 40, 240);
         for (var r:int = 0; r < this._poolRows; r++)
         {
            var y:Number = r * this._rowH;
            var ty:Number = y + (this._rowH - 20) / 2;
            var slot:Object = {};
            // row hit (drawn once; listeners attached once; name/enabled updated per render)
            var hit:Sprite = new Sprite();
            hit.graphics.beginFill(0x000000, 0.004); hit.graphics.drawRect(0, y, this._w, this._rowH); hit.graphics.endFill();
            hit.buttonMode = true; hit.mouseEnabled = false; hit.name = "r-1";
            hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onRowClick);
            hit.addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, this.onRowRightClick);   // 0.0.61 context menu
            hit.addEventListener(MouseEvent.ROLL_OVER, this.onRowOver);
            hit.addEventListener(MouseEvent.ROLL_OUT, this.onRowOut);
            this._rows.addChild(hit); slot.hit = hit;

            if (isCols) {
               var arr:Array = []; var cx:Number = this._markX;
               for (ci = 0; ci < this.columns.length; ci++) {
                  var col:Object = this.columns[ci];
                  var isName:Boolean = (ci == 0);
                  var al:String = (col.align != null) ? col.align : "left";
                  var layoutW:Number = isName ? this._nameNarrowVis : col.w;
                  var f:TextField = Theme.tf(ROW_FS, Theme.PHOS, false, al);
                  var ffmt:TextFormat = f.defaultTextFormat; ffmt.letterSpacing = ROW_LS; f.defaultTextFormat = ffmt;
                  this._rows.addChild(f);
                  f.autoSize = "none";
                  f.width = isName ? 4000 : layoutW;    // NAME renders full text (marquee); others fixed
                  f.height = 20; f.y = ty; f.x = cx;    // ALL geometry before any text
                  f.scrollRect = new Rectangle(0, 0, (isName ? this._nameNarrowVis : layoutW), 20);
                  f.visible = false;
                  arr.push(f);
                  cx += layoutW;
               }
               slot.cols = arr;
            } else {
               var lbl:TextField = Theme.tf(ROW_FS, Theme.PHOS, false, "left");
               var lfmt:TextFormat = lbl.defaultTextFormat; lfmt.letterSpacing = ROW_LS; lbl.defaultTextFormat = lfmt;
               this._rows.addChild(lbl);
               lbl.autoSize = "none"; lbl.width = labelW; lbl.height = 20; lbl.y = ty; lbl.x = this._markX;
               lbl.scrollRect = new Rectangle(0, 0, labelW, 20); lbl.visible = false; slot.lbl = lbl;
               var rt:TextField = Theme.tf(ROW_FS, Theme.PHOS, false, "right");
               var rfmt:TextFormat = rt.defaultTextFormat; rfmt.letterSpacing = ROW_LS; rt.defaultTextFormat = rfmt;
               this._rows.addChild(rt);
               rt.autoSize = "none"; rt.width = rightReserve; rt.height = 20; rt.y = ty; rt.x = this._w - 12 - rightReserve;
               rt.scrollRect = new Rectangle(0, 0, rightReserve, 20); rt.visible = false; slot.rt = rt;
            }
            // separator chip (centred, GROUND background punches the divider line); hidden by default
            var sep:TextField = Theme.tf(12, Theme.PHOS_DIM, true, "center");
            this._rows.addChild(sep);
            sep.autoSize = "none"; sep.width = sepW; sep.height = 18;
            sep.x = (this._w - sepW) / 2; sep.y = y + (this._rowH - 18) / 2;
            sep.background = true; sep.backgroundColor = Theme.GROUND; sep.visible = false; slot.sep = sep;

            this._pool.push(slot);
         }
      }

      // UPDATE-ONLY per render (mouse/key/data driven). Chooses each slot's mode and pushes text/color/visible
      // + graphics; never creates a field or writes geometry (scrollRect for the marquee viewport is exempt).
      public function render():void
      {
         if (!this._pooled) { if (stage == null) { return; } this.buildPool(); }

         this._hoverLayer.graphics.clear();
         this._markers.graphics.clear();
         this._fill.graphics.clear();
         this._selGlow.graphics.clear(); this._selShown = false;   // 0.0.43: recomputed below when the selected row is visible
         this._selMarqField = null; this._hoverMarqField = null; this._marqT = 0; this._nameByIdx = {}; this._hoverIdx = -1;
         // FILLS on _fill (below text); strokes/glyphs on _markers (above text). _rows.graphics carries nothing.
         var g:* = this._fill.graphics;
         this._rows.graphics.clear();

         var count:int = this._entries.length - this._top; if (count > this._visible) { count = this._visible; } if (count < 0) { count = 0; }
         // Iterate the FULL pool and hide every slot past `count` (== past the current _visible window). This
         // cleanly parks the extra expanded-pool rows when collapsed, with no field creation on any path.
         for (var r:int = 0; r < this._poolRows; r++)
         {
            var slot:Object = this._pool[r];
            if (r >= count) { this.hideSlot(slot); continue; }
            var idx:int = this._top + r;
            var e:Object = this._entries[idx];
            var a:Object = this._adapter != null ? this._adapter(e) : { label: String(e), right: "", star: false, legendary: false, dim: false, separator: false };
            var y:Number = r * this._rowH;

            if (a != null && a.separator == true) { this.renderSep(slot, a, y, idx); continue; }

            var isSel:Boolean = (idx == this._sel);
            slot.sep.visible = false;
            slot.hit.name = "r" + idx; slot.hit.mouseEnabled = true;

            if (isSel) {
               this._selGlowY = y; this._selShown = true;   // 0.0.43: pulse target (the glow tick redraws around this row)
               g.beginFill(Theme.SEL, 0.92); g.drawRoundRect(0, y, this._w, this._rowH - 2, 4, 4); g.endFill();
               // P1 (0.0.42): the selection BRACKETS are a manual moveTo/lineTo stroke. Drawn on the shared full-panel
               // pen they bled onto OTHER rows + a diagonal toward the corner (bug: "borders on random rows"). Draw on
               // the dedicated _markers layer (isolated stroke/glyph pen) so only THIS row is bracketed.
               Theme.brackets(this._markers.graphics, 0, y, this._w, this._rowH - 2, 6, Theme.PHOS_BRIGHT, 0.9);
            } else if (idx % 2 == 1) { g.beginFill(Theme.PHOS, 0.03); g.drawRect(0, y, this._w, this._rowH - 2); g.endFill(); }

            // vector markers (font-independent) on their own layer; never shift text.
            //   COLUMNS rows (INV): legendary sparkle LEADS in the left gutter; favorite star TRAILS at the name
            //   column's right edge -- mockup: leading "> Instigating..." sparkle, trailing "Automatic Combat Rifle *"
            //   (parity fix C2). The trailing x is the name column's fixed right edge (no post-text width read).
            //   LABEL rows (DATA/RADIO): both markers lead in the gutter (unchanged).
            var gy:Number = y + this._rowH / 2 - 1;
            var mg:* = this._markers.graphics;
            var isColsRow:Boolean = (slot.cols != null && a.cols != null);
            // 0.0.63: EQUIPPED indicator -- a bright accent bar on the row's LEFT edge (distinct from the faint
            // hover fill and the selection brackets). Marks the currently worn/wielded item in the list.
            if (a.equipped == true) { mg.beginFill(isSel ? 0x0A140A : Theme.PHOS_BRIGHT, 0.95); mg.drawRect(0, y + 2, 2.5, this._rowH - 5); mg.endFill(); }
            if (isColsRow) {
               // legendary sparkle sits in the ~12px left padding, slightly preceding the name (mockup look).
               if (a.legendary) { Theme.legendaryMark(mg, 6, gy, 5, isSel ? 0x0A140A : Theme.WARN); }
               if (a.star) {
                  var nameVis:Number = this.optOn ? this._nameNarrowVis : this._nameWideVis;
                  Theme.star(mg, this._markX + nameVis - 8, gy, 6, isSel ? 0x0A140A : Theme.PHOS_BRIGHT);
               }
            } else {
               var mx:Number = 10;
               if (a.legendary) { Theme.legendaryMark(mg, mx + 4, gy, 6, isSel ? 0x0A140A : Theme.WARN); mx += MARK_STEP; }
               if (a.star)      { Theme.star(mg, mx + 4, gy, 6, isSel ? 0x0A140A : Theme.PHOS_BRIGHT); mx += MARK_STEP; }
            }

            var ink:uint = a.dim ? Theme.PHOS_DIM : Theme.PHOS;
            if (isColsRow) { this.renderCols(slot, a, isSel, idx, ink); }
            else { this.renderLabel(slot, a, isSel, ink); }
         }

         // scroll indicator
         if (this._entries.length > this._visible) {
            var frac:Number = this._top / Math.max(1, (this._entries.length - this._visible));
            var barH:Number = this._visible * this._rowH;
            g.beginFill(Theme.PHOS, 0.5); g.drawRect(this._w - 3, frac * (barH - 30), 3, 30); g.endFill();
         }
      }

      private function renderCols(slot:Object, a:Object, isSel:Boolean, idx:int, ink:uint):void
      {
         var cols:Array = a.cols;
         var fields:Array = slot.cols;
         for (var ci:int = 0; ci < fields.length; ci++) {
            var f:TextField = fields[ci];
            var isName:Boolean = (ci == 0);
            if (ci == this.optCol && !this.optOn) { f.visible = false; continue; }
            f.visible = true;
            if (isName) {
               var vis:Number = this.optOn ? this._nameNarrowVis : this._nameWideVis;
               var rct:Rectangle = f.scrollRect;
               if (rct == null || rct.width != vis) { f.scrollRect = new Rectangle(0, 0, vis, 20); }
               else if (rct.x != 0) { rct.x = 0; f.scrollRect = rct; }
               this.styleField(f, isSel, ink, true, (ci < cols.length ? String(cols[ci]) : ""));
               this._nameByIdx[idx] = f;
               if (isSel) { this._selMarqField = f; }
            } else {
               this.styleField(f, isSel, Theme.PHOS, false, (ci < cols.length ? String(cols[ci]) : ""));
            }
         }
      }

      private function renderLabel(slot:Object, a:Object, isSel:Boolean, ink:uint):void
      {
         slot.lbl.visible = true;
         this.styleField(slot.lbl, isSel, ink, true, String(a.label));
         var hasR:Boolean = (a.right != null && String(a.right).length > 0);
         slot.rt.visible = hasR;
         if (hasR) { this.styleField(slot.rt, isSel, ink, true, String(a.right)); }
      }

      // UPDATE-ONLY separator render. Two flavours share the pooled centred `sep` field (no geometry writes):
      //   plain divider (a.folder != true)  -> mouse-disabled, hairline rule + centred chip label (DATA/RADIO).
      //   folder header  (a.folder == true) -> CLICKABLE: faint band + open/closed caret (vector) + "LABEL (n)".
      // The caret is drawn on the shared _rows pen; the sep field keeps its baked geometry/alignment untouched.
      private function renderSep(slot:Object, a:Object, y:Number, idx:int):void
      {
         this.hideRowFields(slot);
         var midY:Number = y + this._rowH / 2;
         var fg:* = this._fill.graphics;      // band / accent / divider FILLS (below the sep label)
         slot.sep.visible = true;
         if (a.folder == true) {
            slot.hit.mouseEnabled = true; slot.hit.name = "r" + idx; slot.hit.buttonMode = true;
            // #5 FOLDER HEADERS "POP": a strong band fill + a bright left accent bar + top/bottom rules make the
            // folder header read distinctly from item rows at a glance. All self-contained drawRect fills on _fill.
            fg.beginFill(Theme.PHOS, 0.16); fg.drawRect(0, y + 1, this._w, this._rowH - 2); fg.endFill();          // band
            fg.beginFill(Theme.PHOS_BRIGHT, 0.85); fg.drawRect(0, y + 2, 3, this._rowH - 4); fg.endFill();          // left accent bar
            fg.beginFill(Theme.PHOS, 0.40); fg.drawRect(0, y, this._w, 1); fg.endFill();                            // top rule
            fg.beginFill(Theme.PHOS, 0.22); fg.drawRect(0, y + this._rowH - 2, this._w, 1); fg.endFill();           // bottom rule
            // caret on the dedicated _markers layer (manual moveTo/lineTo path; never the shared fill pen).
            this.drawFolderCaret(this._markers.graphics, 14, midY, (a.collapsed == true));
            var cnt:String = (a.count != null) ? ("  (" + int(a.count) + ")") : "";
            Theme.setText(slot.sep, String(a.label) + cnt);
            slot.sep.textColor = Theme.PHOS_BRIGHT;   // bold BRIGHT label (vs the dim divider chip)
         } else {
            slot.hit.mouseEnabled = false;
            fg.beginFill(Theme.PHOS_DIM, 0.5); fg.drawRect(10, midY, this._w - 20, 1); fg.endFill();   // hairline rule (fill, not stroke)
            Theme.setText(slot.sep, "  " + String(a.label) + "  ");
            slot.sep.textColor = Theme.PHOS_DIM;
         }
      }

      // Font-independent folder caret (graphics only): collapsed -> right-pointing, open -> down-pointing. Drawn on
      // the dedicated _markers layer; lineStyle() reset first so it can never inherit a stroke or connect a pen path.
      private function drawFolderCaret(g:*, cx:Number, cy:Number, collapsed:Boolean):void
      {
         g.lineStyle(0, 0, 0);
         g.beginFill(Theme.PHOS_BRIGHT, 1);
         if (collapsed) { g.moveTo(cx - 2, cy - 4); g.lineTo(cx + 4, cy); g.lineTo(cx - 2, cy + 4); }
         else           { g.moveTo(cx - 4, cy - 2); g.lineTo(cx + 4, cy - 2); g.lineTo(cx, cy + 4); }
         g.endFill();
      }

      // Selected-row bold via defaultTextFormat (setText re-applies it through setTextFormat); selected rows
      // get Theme.selectedInk (near-white ink + dark shadow, the locked M1 look) AFTER setText, unselected rows
      // clear filters and restore their ink.
      private function styleField(f:TextField, isSel:Boolean, unselColor:uint, boldWhenSel:Boolean, str:String):void
      {
         var fmt:TextFormat = f.defaultTextFormat;
         fmt.bold = (isSel && boldWhenSel);
         fmt.color = unselColor;
         f.defaultTextFormat = fmt;
         Theme.setText(f, str);
         if (isSel) { Theme.selectedInk(f); }
         else { f.filters = []; f.textColor = unselColor; }
      }

      private function hideRowFields(slot:Object):void
      {
         if (slot.cols != null) { for (var i:int = 0; i < slot.cols.length; i++) { slot.cols[i].visible = false; } }
         if (slot.lbl != null) { slot.lbl.visible = false; }
         if (slot.rt != null) { slot.rt.visible = false; }
      }
      private function hideSlot(slot:Object):void
      {
         slot.hit.mouseEnabled = false; slot.hit.name = "r-1";
         this.hideRowFields(slot);
         slot.sep.visible = false;
      }
   }
}
