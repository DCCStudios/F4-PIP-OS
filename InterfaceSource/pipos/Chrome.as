package pipos
{
   import flash.display.Sprite;
   import flash.display.Graphics;
   import flash.display.GradientType;
   import flash.display.Loader;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.geom.Matrix;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.text.TextField;

   // PIP-OS chrome, DLL-ROUTE. Loaded as a ROOT CHILD of the byte-identical vanilla Pip-Boy movie by the
   // companion DLL (S2 pattern). The shell is UNTOUCHED, so it never calls updateData(); the chrome
   // SELF-ACQUIRES the menu via stage.getChildAt(0)["Menu_mc"] (PipboyTabs idiom) and drives page switching
   // through the vanilla-public PipboyMenu.TryToSetPage(uint). The DLL dims Header_mc; this chrome does NOT
   // double-dim.
   //
   // ROUND 30 (0.0.24-WIDE) - 16:9 RE-AUTHOR. Everything is now laid out to the M1 mockup (1600x900 canvas)
   // via Theme.mx()/my()/ms() (single-knob origin fix). The chrome owns: the CRT bezel (rounded frame +
   // corner L-brackets), the thin top telemetry strip, the vertical left tab column (page tabs + flavor
   // codes + EXTENSIONS/[EXT] group + clock card), AND the CRT polish overlay (rolling scanlines eased in on
   // open, edge vignette, central phosphor glow) - all drawn over the whole frame, MOUSE-TRANSPARENT.
   //
   // DISCIPLINE (rounds 17-19, mechanical): NO TextField created before on-stage; ALL fields pooled ONCE in
   // buildText(); draw/tick handlers UPDATE text/color + redraw GRAPHICS only, NEVER create a field and NEVER
   // set .width on a text field (SetWidth = the FindFont crash vector; ctor_text_check gates
   // onTick/onTabHit/acquireMenu/paintTabs). GRACEFUL: every menu access is try/caught; a failed acquire =
   // blank chrome, never a CTD. The CRT overlay is graphics-only (no text), animated time-based via Ticker.
   public class Chrome extends Sprite
   {
      private static const PAGES:Array = ["STAT","INV","DATA","MAP","RADIO"];
      // Dim FLAVOR codes shown under tabs 0..3 (documented flavor per the "every element has purpose" rule).
      private static const CODES:Array = ["INV 04.JK.E","DB 1A.F7.G","GPS 77.7F.E","SIG S.T60.B"];
      private static const EXTS:Array = ["CHALLENGES","AFFINITY","MAGAZINES"];

      // World-dim veil opacity. History: 0.42 (0.0.27) near-black; 0.20 (0.0.28) still over-dimmed in game.
      // 0.0.29 root cause of the over-dim = the veil STACKED across Pip-Boy re-opens (each open reloads the
      // chrome and re-ran attachVeil on the PERSISTENT root1; the old guard SKIPPED when a veil already existed
      // but never removed a stale one, so alpha piled up open-over-open). attachVeil now REMOVES any existing
      // veil first so exactly ONE veil is ever present, and this drops to 0.10. A single in-game screenshot
      // decides whether 0.10 is right; if it is STILL too dark with anti-stack, the darkness is NOT the veil
      // (it would point to Baka's own compositing), not more veil tuning.
      private static const VEIL_ALPHA:Number = 0.10;

      // Sidebar column geometry, in MOCKUP px (sidebar top60 left34 W176). The mockup flex column stacks a
      // 54px tab + 9px gap + ~13px flavor-code row + 9px gap per unit; these are the resulting box tops.
      private static const TAB_MY:Array = [60, 145, 230, 315, 400];  // page-tab box tops (mockup Y)
      private static const NOTE_MY:Array = [123, 208, 293, 378];     // flavor-code row Y under tabs 0..3
      private static const EXT_HDR_MY:Number = 468;                  // "EXTENSIONS - PIPBOYTABS" label Y
      private static const EXT_MY:Array = [490, 537, 584];           // ext-tab box tops (mockup Y)
      private static const CLOCK_MY:Number = 748;                    // clock card top (mockup Y)

      // 0.0.37 CRT LIFE + POWER-ON (mockup parity). Chrome-LOCAL feature toggles (NOT in Theme.as, so a later
      // Menu Framework round can gate these by pushing settings; editing these here rebuilds ONLY PipOS_Chrome.swf).
      // Default ON but deliberately SUBTLE + SLOW (no strobing / seizure risk; reduced-motion off-switch = flip
      // the const). All three are GRAPHICS + Sprite .alpha / container-transform ONLY (no TextField geometry).
      private static const OPEN_ANIM:Boolean = true;    // FEATURE B: phosphor power-on fade of chrome+veil on attach
      private static const CRT_BREATHE:Boolean = true;  // FEATURE A: slow sinusoidal breathe on the phosphor glow alpha
      private static const CRT_SWEEP:Boolean = true;    // FEATURE A: periodic soft bright band sweeping top->bottom
      // FEATURE B open fade (mockup #scanin / crtopen, kept short so it does NOT fight the engine's physical raise).
      private static const OPEN_DUR:Number = 0.30;      // seconds; smoothstep 0->1 on this.alpha + veil.alpha
      // FEATURE A breathe (mockup living-phosphor feel). Period ~6s; glow Sprite.alpha oscillates GLOW_BASE +/- GLOW_AMP
      // (0.85 +/- 0.14 ~= +/-16.5% about the base -> subtle, never a flicker).
      private static const BREATHE_PERIOD:Number = 6.0;
      private static const GLOW_BASE:Number = 0.85;
      private static const GLOW_AMP:Number = 0.14;
      // FEATURE A scan sweep (mockup #scanroll::after / scansweep 9s ease-in-out). Soft band travels the frame every
      // ~9s, alpha-eased at both ends. Band height ~26% of the frame (matches the mockup 26%).
      private static const SWEEP_PERIOD:Number = 9.0;
      private static const SWEEP_H:Number = 198;        // ~0.26 * FRAME_H
      // Full visible frame (root1-local budget from the 16:9 spike), shared by buildCRT + the sweep travel math.
      private static const FRAME_X:Number = -238;
      private static const FRAME_Y:Number = 0;
      private static const FRAME_W:Number = 1352;
      private static const FRAME_H:Number = 761;

      // 0.0.44 CRT POWER-ON (FEATURE B rework). The old open anim was a flat 0.3s container alpha fade, which the
      // user flagged as "nothing like the mockup." Replaced by a real CRT turn-on: two black shutters cover the
      // top+bottom halves and RETRACT from the vertical center (scaleY 1->0), revealing the picture as a slit that
      // opens vertically, followed by a brief phosphor bloom that settles. All Sprite scaleY/.alpha/.visible only
      // (container transforms) -> no TextField geometry, so the FindFont(NULL) crash law holds. Kept ~0.5s total so
      // it reads as a power-on without fighting the engine's physical Pip-Boy raise.
      private static const POWER_REVEAL:Number = 0.22;   // shutters open (black -> slit -> full picture)
      private static const POWER_FLASH:Number = 0.28;    // phosphor bloom settle after the reveal completes

      // 0.0.52 forensics: mirror of Theme.LIFE (the shared lifecycle-breadcrumb trail all pages append to).
      // Chrome copies it here each tick; the DLL reads root1.PipOS_chrome_loader.content.PipOS_life and logs it,
      // giving in-game proof of how far each page's class got even when a page never renders.
      public var PipOS_life:String = "";

      private var _menu:Object = null;
      private var _acquired:Boolean = false;
      private var _built:Boolean = false;
      private var _bg:Sprite;                   // CRT bezel / frame border (below tabs)
      private var _tabBar:Sprite;               // holds tab label/hit children; .graphics = boxes+icons+accents
      private var _crt:Sprite;                  // CRT polish overlay (mouse-transparent, topmost)
      private var _glow:Sprite;                 // central phosphor glow layer (FEATURE A: breathe via .alpha)
      private var _sweep:Sprite;                // soft bright band (FEATURE A: scan sweep via .y + .alpha)
      private var _scan:Sprite;                 // rolling scanline layer inside _crt
      private var _power:Sprite;                // CRT power-on layer (topmost, mouse-transparent): shutters+flash+seam
      private var _shTop:Sprite;                // top black shutter (retracts up via scaleY on open)
      private var _shBot:Sprite;                // bottom black shutter (retracts down via scaleY on open)
      private var _flash:Sprite;                // phosphor bloom that settles after the reveal
      private var _seam:Sprite;                 // bright center seam line marking the opening slit
      private var _tabLabels:Array = [];
      private var _tabHits:Array = [];
      private var _tabY:Array = [];
      private var _codeLabels:Array = [];
      private var _extLabels:Array = [];
      private var _extHits:Array = [];
      private var _extY:Array = [];
      private var _clockDate:TextField;
      private var _clockTime:TextField;
      private var _tel:TextField;
      private var _ticker:Ticker;
      private var _lastPage:int = -99;
      private var _hoverIdx:int = -99;          // P1-B: hovered tab index (page 0..4, ext 5..7); -99 = none
      // 0.0.56 SHELL MEDIC state (see onTick). _medicFlagStuck = the shell's private _IsLoadingPage could not be
      // cleared after a heal, so the chrome substitutes the event pump; _medicRedisp paces that re-dispatch.
      private var _medicFlagStuck:Boolean = false;
      private var _medicRedisp:Number = 0;
      private var _pumpLastPage:int = -99;      // 0.0.57: instant re-dispatch when the native page/tab changes
      private var _pumpLastTab:int = -99;

      // 0.0.57 PAGE-DEF PRELOADER. Root cause of the FindFont(NULL) page-switch CTDs (radio/data crash stacks):
      // pipos.* classes + the embedded font follow first-def-wins -- whichever SWF loads FIRST donates them for the
      // whole session. The shell's ClearPages() unloadAndStop()s ALL page loaders on EVERY page switch; when a PAGE
      // SWF (not the chrome) won the first-def race, the switch UNLOADS the font donor and the incoming page's
      // buildText formats against a dead font -> native FindFont(NULL) AV. Fix: GFx caches MovieDefs by URL, so the
      // chrome preloads every page SWF into hidden loaders it NEVER unloads -> every page's resources (font incl.)
      // stay resident regardless of ClearPages. Loaders are never added to the display list.
      private var _preloaders:Array = null;
      private function preloadPageDefs():void
      {
         if (this._preloaders != null) { return; }   // once per chrome instance (per open; defs cached anyway)
         this._preloaders = [];
         var urls:Array = ["Pipboy_StatsPage.swf", "Pipboy_InvPage.swf", "Pipboy_DataPage.swf", "Pipboy_MapPage.swf", "Pipboy_RadioPage.swf"];
         for (var i:int = 0; i < urls.length; i++) {
            try {
               var ld:Loader = new Loader();
               ld.load(new URLRequest(String(urls[i])), new LoaderContext(false, ApplicationDomain.currentDomain));
               this._preloaders.push(ld);
            } catch (ep:*) {}
         }
      }

      private var _crtT:Number = 0;             // seconds since open (scanline ease-in + breathe phase)
      private var _roll:Number = 0;             // scanline roll phase (0..3 px)
      private var _sweepT:Number = 0;           // FEATURE A: scan-sweep phase (0..SWEEP_PERIOD s)
      private var _openT:Number = 0;            // FEATURE B: elapsed open-fade time (0..OPEN_DUR s)
      private var _powerT:Number = 0;           // 0.0.44 CRT power-on elapsed time (0..POWER_REVEAL+POWER_FLASH)
      private var _powerOn:Boolean = false;     // 0.0.44 power-on sequence active this open
      private var _veil:Sprite = null;          // the veil Sprite itself (FEATURE B: fade its .alpha in on open)
      private var _veilRoot:* = null;           // root1 the veil was added to (for teardown on REMOVED_FROM_STAGE)
      private var _dbg:Debug;

      // 0.0.38 RUNTIME OVERRIDES (F4SE Menu Framework). Initialised to the CONST defaults above so that with
      // NO settings object (old DLL / no DLL / read failure) the chrome is byte-identical to 0.0.37. readSettings()
      // (called once at attach, before attachVeil) replaces these from root1.PipOS_settings when present. All three
      // are consumed only via graphics fill alpha (veil) or as booleans gating a Sprite/container .alpha write --
      // no TextField, no geometry -- so the CRASH LAW holds.
      private var _veilAlpha:Number = VEIL_ALPHA;
      private var _openSpeed:Number = 1;        // 0.0.60: power-on speed multiplier (settings slider; 0.25-4)
      private var _openAnim:Boolean = OPEN_ANIM;
      private var _breathe:Boolean = CRT_BREATHE;

      // resolved local-space geometry (set once in buildText from Theme.mx/my/ms).
      private var BX:Number, BW:Number, TABH:Number, EXTH:Number;

      public function Chrome()
      {
         super();
         Theme.life("CH.c");   // 0.0.52 forensics
         Fonts.register();
         this.mouseEnabled = false; this.mouseChildren = true;   // only the tab hit rects consume mouse
         this._bg = new Sprite(); this._bg.mouseEnabled = false; this._bg.mouseChildren = false; addChild(this._bg);
         this._tabBar = new Sprite(); addChild(this._tabBar);
         this._dbg = new Debug("CHROME"); addChild(this._dbg);
         addEventListener(Event.ADDED_TO_STAGE, this.onAdded);
         addEventListener(Event.REMOVED_FROM_STAGE, this.onRemoved);   // 0.0.29: tear the veil down so a closed Pip-Boy leaves no orphan
      }

      // 0.0.29: on chrome teardown (Pip-Boy close / re-load), stop the ticker and REMOVE the veil from root1 so
      // no orphaned veil survives to stack on the next open. Guarded; a failure is silent (never a CTD).
      private function onRemoved(e:Event):void
      {
         try { if (this._ticker != null) { this._ticker.stop(); } } catch (er:*) {}
         this.removeVeil();
      }

      private function onAdded(e:Event):void
      {
         removeEventListener(Event.ADDED_TO_STAGE, this.onAdded);
         // P0-B (0.0.25): the DLL wraps this chrome in a flash.display.Loader added as a root1 child ABOVE
         // Menu_mc. That Loader defaults to mouseEnabled=true with frame-spanning bounds (our CRT overlay
         // covers the whole frame), so GFx returns the Loader as the hit target for every point NOT over a
         // chrome tab and mouse never falls through to the pages under Menu_mc (page subtabs / list rows /
         // hover were all dead while only the chrome sidebar tabs worked). Mirror the chrome's OWN proven
         // pattern one level up: Loader.mouseEnabled=false + mouseChildren=true keeps the deeper tab-hit
         // children alive AND lets non-tab mouse fall through to the page layer. This is safe by the same
         // evidence the tabs work at all: the chrome sprite itself is mouseEnabled=false/mouseChildren=true.
         try { if (this.parent != null) { this.parent.mouseEnabled = false; this.parent.mouseChildren = true; } } catch (er:*) {}
         if (this._dbg != null) { this._dbg.mark("added"); }
         this.preloadPageDefs();   // 0.0.57: pin every page SWF's MovieDef (font incl.) for the whole session
         this.readSettings();  // 0.0.38: pull veil/breathe/openAnim overrides from root1.PipOS_settings BEFORE attachVeil uses them
         this.attachVeil();   // P1 (0.0.26): world-dim layer BEHIND the pages (root1 index 0)
         this.acquireMenu();
         this.buildText();
         // FEATURE B (0.0.37): phosphor power-on. Start the chrome container AND the world-dim veil transparent;
         // onTick smoothsteps both to full over OPEN_DUR (~0.3s) so the DLL-loaded chrome REVEALS rather than POPS.
         // Purely visual container/Sprite .alpha (no geometry, no TextField touch); kept short so it never fights
         // the engine's own physical Pip-Boy raise.
         // REOPEN FIX (0.0.37 ship-blocker): the DLL re-adds the SAME persistent chrome instance on every open, so
         // this runs again per open. _openT only ever accumulates, so WITHOUT resetting it here the 2nd+ open would
         // re-zero alpha while _openT>=OPEN_DUR -> the ramp gate (_openT<OPEN_DUR) is false -> alpha stays 0 forever
         // ("works once, invisible forever"). Reset the fade clock (and the CRT ease/sweep clocks, so the scanline
         // ease-in + sweep re-ease cleanly instead of snapping to full) every open. The ELSE branch is the fail-safe:
         // if OPEN_ANIM is ever off, the chrome must land FULLY VISIBLE (alpha 1 + veil Sprite at its natural full
         // alpha, the 0.10 dim living in the veil FILL), never stuck <1.
         // 0.0.44: the picture is now revealed by the CRT power-on SHUTTERS (buildPower), not a container alpha
         // fade, so the chrome + veil come up FULLY VISIBLE and the black shutters on top do the reveal. Arm (or,
         // if the anim is off, immediately clear) the power-on layer. All Sprite scaleY/.alpha/.visible only.
         this._crtT = 0; this._sweepT = 0;
         this._medicFlagStuck = false; this._medicRedisp = 0;   // 0.0.56: fresh shell per open = fresh medic state
         this.alpha = 1; if (this._veil != null) { this._veil.alpha = 1; }
         if (this._openAnim) {
            this._powerT = 0; this._powerOn = true;
            if (this._shTop != null) { this._shTop.scaleY = 1; this._shTop.visible = true; }
            if (this._shBot != null) { this._shBot.scaleY = 1; this._shBot.visible = true; }
            if (this._flash != null) { this._flash.alpha = 0; this._flash.visible = true; }
            if (this._seam != null)  { this._seam.alpha = 0.9; this._seam.visible = true; }
         } else {
            this._powerOn = false;
            if (this._shTop != null) { this._shTop.visible = false; }
            if (this._shBot != null) { this._shBot.visible = false; }
            if (this._flash != null) { this._flash.visible = false; }
            if (this._seam != null)  { this._seam.visible = false; }
         }
         if (this._ticker == null) { this._ticker = new Ticker(this, this.onTick); }
         this._ticker.start();
      }

      // P1 (0.0.26) "HOLE IN THE MIDDLE" fix. The live 3D world shows through BRIGHT + sharp only in Baka's
      // central Pip-Boy screen region; the CRT overlay sits ABOVE the pages so it can't dim that center without
      // also dimming our own panels/text. The mockup dims the world UNIFORMLY behind everything. We can't blur
      // the live world, but we CAN dim it, and the dim must sit BEHIND the pages. Architecture: add a
      // semi-transparent dark full-frame Sprite into root1 (== stage.getChildAt(0), the vanilla PipboyMenu
      // movie root, the same node the chrome/DLL already reach) at index 0 -> BENEATH Menu_mc (pages) and the
      // chrome Loader, but ABOVE the world that shows through the movie. Result: the world + Baka's background
      // art dim uniformly; our pages and chrome render on top, unaffected. AS-only (no DLL change). Every step
      // is guarded (blank-no-veil, never a CTD) and idempotent (named child, skip if already present). This is
      // in-game-gated for the actual world-dim (a preview has no live-world stand-in behind root1), but it is
      // structurally the correct layer and cannot darken our own UI (it is strictly below Menu_mc).
      // 0.0.38: read the DLL-pushed customization object off root1 (same node + idiom as PipOS_equip et al.).
      // Fully guarded + per-member validated: a missing object OR a missing/invalid member leaves the const
      // default in place, so the worst case is EXACTLY 0.0.37 behavior. Reads only (no field, no geometry).
      private function readSettings():void
      {
         try {
            if (stage == null || stage.numChildren == 0) { return; }
            var root1:* = stage.getChildAt(0);
            if (root1 == null) { return; }
            var s:* = root1.PipOS_settings;
            if (s == null) { return; }
            if (s.hasOwnProperty("veil")) {
               var v:Number = Number(s.veil);
               if (!isNaN(v) && v >= 0 && v <= 1) { this._veilAlpha = v; }
            }
            if (s.hasOwnProperty("openAnim")) { this._openAnim = (s.openAnim == true); }
            if (s.hasOwnProperty("breathe")) { this._breathe = (s.breathe == true); }
            // 0.0.60: open-animation SPEED multiplier (user slider). 1.0 = shipped timing; 2.0 = twice as fast.
            if (s.hasOwnProperty("openAnimSpeed")) {
               var os:Number = Number(s.openAnimSpeed);
               if (!isNaN(os) && os >= 0.25 && os <= 4) { this._openSpeed = os; }
            }
            if (this._dbg != null) { this._dbg.mark("setOK"); }
         } catch (er:*) { if (this._dbg != null) { this._dbg.mark("setFAIL"); } }
      }

      private function attachVeil():void
      {
         try {
            if (stage == null || stage.numChildren == 0) { return; }
            var root1:* = stage.getChildAt(0);
            if (root1 == null) { return; }
            // ANTI-STACK (0.0.29): root1 PERSISTS across Pip-Boy re-opens; each open reloads the chrome and
            // re-runs attachVeil. The old guard SKIPPED when a veil already existed but never removed a stale
            // one, so veils could pile up (or a second this-instance veil could be added) -> alpha STACKED to
            // near-black. Now REMOVE any existing "PipOS_veil" first, then add exactly ONE fresh veil, so no
            // matter how many opens exactly one veil is ever present.
            try { var old:* = root1.getChildByName("PipOS_veil"); if (old != null) { root1.removeChild(old); } } catch (e0:*) {}
            var veil:Sprite = new Sprite();
            veil.name = "PipOS_veil";
            veil.mouseEnabled = false; veil.mouseChildren = false;   // never eats a click (it's below pages anyway)
            var g:Graphics = veil.graphics;
            g.beginFill(0x000000, this._veilAlpha); // 0.0.38: runtime veil alpha (settings override; falls back to VEIL_ALPHA=0.10)
            g.drawRect(-260, -20, 1400, 800);     // generously spans the visible frame budget (X[-238,1114] Y[0,761])
            g.endFill();
            root1.addChildAt(veil, 0);            // beneath Menu_mc + chrome loader, above the world
            this._veil = veil;                    // FEATURE B: keep the ref so the open-fade can ramp its .alpha
            this._veilRoot = root1;               // remember for teardown (stage may be null on removal)
            if (this._dbg != null) { this._dbg.mark("veilOK"); }
         } catch (er:*) { if (this._dbg != null) { this._dbg.mark("veilFAIL"); } }
      }

      // 0.0.29 teardown: remove the veil from root1 so a closed Pip-Boy leaves no orphan to stack on next open.
      // Uses the remembered _veilRoot (stage is often already null by REMOVED_FROM_STAGE). Guarded; silent on fail.
      private function removeVeil():void
      {
         try {
            var root1:* = (this._veilRoot != null) ? this._veilRoot : ((stage != null && stage.numChildren > 0) ? stage.getChildAt(0) : null);
            if (root1 == null) { return; }
            var v:* = root1.getChildByName("PipOS_veil");
            if (v != null) { root1.removeChild(v); if (this._dbg != null) { this._dbg.mark("veilGone"); } }
         } catch (er:*) {}
      }

      // Self-acquire the vanilla PipboyMenu instance. NO-OP silently on any failure (no CTD).
      private function acquireMenu():void
      {
         try {
            if (stage != null && stage.numChildren > 0) { this._menu = stage.getChildAt(0)["Menu_mc"]; }
            this._acquired = (this._menu != null);
         } catch (er:*) { this._menu = null; this._acquired = false; }
         if (this._dbg != null) { this._dbg.mark(this._acquired ? "menuOK" : "menuFAIL"); }
      }

      // ON-STAGE ONLY: create every TextField ONCE (addChild before text via Theme.mk/setText). Never create
      // a field in a tick/draw handler; never set .width on one.
      private function buildText():void
      {
         if (this._built) { return; }
         this._built = true;

         this.BX = Theme.mx(34); this.BW = Theme.ms(176); this.TABH = Theme.ms(54); this.EXTH = Theme.ms(38);

         // (0) CRT bezel: rounded frame border inset from the screen (mockup #frame 16/26/16/16, r10) + 16px
         //     corner L-brackets. Faint line body, brighter corner accents. Drawn once into _bg (below tabs).
         this.drawBezel();

         // (1) thin top telemetry strip (mockup #topstrip y0..34; text ~y11). Left boxed OS id, center NFO,
         //     right property tag. Positioned by READING width (read is safe).
         var stripY:Number = Theme.my(9);
         var topL:TextField = Theme.mk(this, 11, Theme.PHOS_DIM, true); topL.x = Theme.mx(24); topL.y = stripY; Theme.setText(topL, "PIP-BOY OS  V2.7.1");
         // boxed OS id (mockup .os border)
         var bg:Graphics = this._bg.graphics;
         bg.lineStyle(1, Theme.LINE, 0.38); bg.drawRect(Theme.mx(24) - 6, stripY - 2, topL.width + 12, 17); bg.lineStyle();
         var topC:TextField = Theme.mk(this, 11, Theme.PHOS_FAINT, false); topC.y = stripY; Theme.setText(topC, "SSS NFO 3247-98A   -   CONNECTION: STABLE"); topC.x = (Theme.CX + Theme.CR) / 2 - topC.width / 2;
         var topR:TextField = Theme.mk(this, 11, Theme.PHOS_DIM, true); topR.y = stripY; Theme.setText(topR, "PROPERTY OF VAULT-TEC"); topR.x = Theme.mx(1578) - topR.width;

         // (2) vertical page-tab column
         for (var i:int = 0; i < PAGES.length; i++) {
            var ty:Number = Theme.my(Number(TAB_MY[i]));
            this._tabY.push(ty);
            var lbl:TextField = Theme.mk(this._tabBar, 15, Theme.PHOS_DIM, true); lbl.x = this.BX + 40; lbl.y = ty + this.TABH / 2 - 10; Theme.setText(lbl, String(PAGES[i]));
            this._tabLabels.push(lbl);
            var hit:Sprite = new Sprite(); hit.graphics.beginFill(0, 0.004); hit.graphics.drawRect(this.BX, ty, this.BW, this.TABH); hit.graphics.endFill();
            hit.name = "pt" + i; hit.buttonMode = true; hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onTabHit);
            hit.addEventListener(MouseEvent.ROLL_OVER, this.onTabOver); hit.addEventListener(MouseEvent.ROLL_OUT, this.onTabOut);   // P1-B
            this._tabBar.addChild(hit); this._tabHits.push(hit);
            if (i < CODES.length) {
               var code:TextField = Theme.mk(this._tabBar, 9, Theme.PHOS_FAINT, false); code.x = this.BX + 40; code.y = Theme.my(Number(NOTE_MY[i])); Theme.setText(code, String(CODES[i]));
               this._codeLabels.push(code);
            }
         }

         // (3) EXTENSIONS - PIPBOYTABS group
         var extHdr:TextField = Theme.mk(this._tabBar, 9, Theme.PHOS_DIM, true); extHdr.x = this.BX; extHdr.y = Theme.my(EXT_HDR_MY); Theme.setText(extHdr, "EXTENSIONS - PIPBOYTABS");
         for (var j:int = 0; j < EXTS.length; j++) {
            var ey:Number = Theme.my(Number(EXT_MY[j]));
            this._extY.push(ey);
            var elbl:TextField = Theme.mk(this._tabBar, 12, Theme.PHOS_DIM, true); elbl.x = this.BX + 22; elbl.y = ey + this.EXTH / 2 - 8; Theme.setText(elbl, String(EXTS[j]));
            this._extLabels.push(elbl);
            // P2 (0.0.27): geometry-before-text. badge.y is the FIXED slot, so set it on the fresh empty field
            // BEFORE setText (was the FindFont geometry-after-text pattern; stable only because chrome's font is
            // resolved at attach). badge.x legitimately reads .width for right-align, so it stays AFTER text --
            // the designated-safe .x-by-width-read reposition.
            var badge:TextField = Theme.mk(this._tabBar, 8, Theme.PHOS_FAINT, true); badge.y = ey + this.EXTH / 2 - 6; Theme.setText(badge, "[EXT]"); badge.x = this.BX + this.BW - 8 - badge.width;
            var ehit:Sprite = new Sprite(); ehit.graphics.beginFill(0, 0.004); ehit.graphics.drawRect(this.BX, ey, this.BW, this.EXTH); ehit.graphics.endFill();
            ehit.name = "ex" + j; ehit.buttonMode = true; ehit.addEventListener(MouseEvent.MOUSE_DOWN, this.onTabHit);
            ehit.addEventListener(MouseEvent.ROLL_OVER, this.onTabOver); ehit.addEventListener(MouseEvent.ROLL_OUT, this.onTabOut);   // P1-B
            this._tabBar.addChild(ehit); this._extHits.push(ehit);
         }

         // (4) clock card, bottom-left of the column (mockup #clockcard: date bright / time / version faint).
         // 0.0.44: the user flagged this box as reading BRIGHTER/heavier than the nav tabs and the "PIP-OS(R)"
         // version line spilling BELOW the box. Both fixed: border alpha dropped 0.38 -> 0.22 (== inactive nav
         // tab border) and fill 0.82 -> 0.50 so the card sits with the nav column instead of popping; card
         // height 66 -> 90 (matches the mockup's ~90px box) so all three lines fit INSIDE with padding.
         var clY:Number = Theme.my(CLOCK_MY);
         var clH:Number = Theme.ms(90);
         bg.beginFill(Theme.PANEL, 0.50); bg.drawRoundRect(this.BX, clY, this.BW, clH, 8, 8); bg.endFill();
         bg.lineStyle(1, Theme.LINE, 0.22); bg.drawRoundRect(this.BX, clY, this.BW, clH, 8, 8); bg.lineStyle();
         this._clockDate = Theme.mk(this, 16, Theme.PHOS_BRIGHT, true, "center"); this._clockDate.autoSize = "none"; this._clockDate.width = this.BW; this._clockDate.x = this.BX; this._clockDate.y = clY + 10; Theme.setText(this._clockDate, "--.--.----");
         this._clockTime = Theme.mk(this, 13, Theme.PHOS, false, "center"); this._clockTime.autoSize = "none"; this._clockTime.width = this.BW; this._clockTime.x = this.BX; this._clockTime.y = clY + 33; Theme.setText(this._clockTime, "--:--");
         this._tel = Theme.mk(this, 9, Theme.PHOS_FAINT, false, "center"); this._tel.autoSize = "none"; this._tel.width = this.BW; this._tel.x = this.BX; this._tel.y = clY + 54; Theme.setText(this._tel, "PIP-OS(R)  V2.7.1");

         // NOTE: the bottom button-prompt bar is NOT drawn here. It is PER PAGE (Theme.keybar) because the wired
         // prompts differ by tab (INV inspect/drop/... vs DATA show-on-map/summary vs RADIO tune, etc.); a single
         // global bar would show foreign/dead prompts on most tabs. The chrome owns only the frame + CRT polish.

         // (5) CRT polish overlay (topmost, mouse-transparent). Built after all content so it sits on top.
         this.buildCRT();

         // (6) CRT power-on layer (ABOVE the polish overlay, mouse-transparent): shutters + phosphor bloom.
         this.buildPower();

         this.paintTabs(this._lastPage);   // initial draw (all inactive until first tick reads CurrentPage)
         if (this._dbg != null) { this._dbg.mark("built"); }
      }

      // CRT bezel: rounded frame border + corner L-brackets (mockup #frame). Drawn once into _bg.
      private function drawBezel():void
      {
         var g:Graphics = this._bg.graphics;
         var x0:Number = Theme.mx(16), y0:Number = Theme.my(26), x1:Number = Theme.mx(1584), y1:Number = Theme.my(884);
         var r:Number = Theme.ms(10);
         g.lineStyle(1, Theme.LINE, 0.16); g.drawRoundRect(x0, y0, x1 - x0, y1 - y0, r, r); g.lineStyle();
         var L:Number = Theme.ms(18);   // corner bracket arm length
         g.lineStyle(1.5, Theme.LINE, 0.75);
         g.moveTo(x0, y0 + L); g.lineTo(x0, y0); g.lineTo(x0 + L, y0);                 // TL
         g.moveTo(x1 - L, y0); g.lineTo(x1, y0); g.lineTo(x1, y0 + L);                 // TR
         g.moveTo(x0, y1 - L); g.lineTo(x0, y1); g.lineTo(x0 + L, y1);                 // BL
         g.moveTo(x1 - L, y1); g.lineTo(x1, y1); g.lineTo(x1, y1 - L);                 // BR
         g.lineStyle();
      }

      // Build the CRT polish overlay: gentle central phosphor glow + SOFT edge vignette + rolling scanline
      // layer. All graphics-only; mouseEnabled/mouseChildren=false so it NEVER eats a click.
      // P1-A (0.0.25): the old overlay drew 4x150px BLACK bands at alpha 0.5 on the BEZEL INSET only -> it read
      // as a heavy dark border around a bright center "hole" and never reached the screen edges. Now: (a) cover
      // the FULL visible frame (root1-local budget from the 16:9 spike, X[-238,1114] Y[0,761]) so it fills the
      // screen; (b) drop the vignette to LOW alpha (0.20) with WIDE bands + smooth falloff -> gentle darkening
      // that reaches well inward with NO hard center hole; (c) keep the subtle scanlines as the PRIMARY texture.
      private function buildCRT():void
      {
         this._crt = new Sprite(); this._crt.mouseEnabled = false; this._crt.mouseChildren = false; addChild(this._crt);
         var fx:Number = FRAME_X, fy:Number = FRAME_Y, fw:Number = FRAME_W, fh:Number = FRAME_H;   // full visible frame (root1-local)
         var g:Graphics = this._crt.graphics;

         // SOFT edge vignette (four LINEAR bands, low alpha, wide + smooth falloff dark->transparent inward;
         // linear gradients render reliably in GFx, so a failure can't flat-darken the screen). Bands overlap
         // gently at the corners (~0.36) for a natural vignette; the large clear center = no hard hole. Drawn
         // into _crt.graphics (static).
         var vb:Number = 230, va:Number = 0.20;
         this.vignetteBand(g, fx, fy, fw, vb, 90, va);              // top
         this.vignetteBand(g, fx, fy + fh - vb, fw, vb, 270, va);   // bottom
         this.vignetteBand(g, fx, fy, vb, fh, 0, va);               // left
         this.vignetteBand(g, fx + fw - vb, fy, vb, fh, 180, va);   // right

         // FEATURE A (0.0.37) BREATHE: gentle central phosphor glow, now on its OWN pooled Sprite so onTick can
         // "breathe" it by Sprite.alpha ONLY (no redraw, no text). Drawn once; a mis-honoured radial degrades to a
         // faint flat tint. Base alpha lives in the fill; the living oscillation is GLOW_BASE +/- GLOW_AMP on .alpha.
         this._glow = new Sprite(); this._glow.mouseEnabled = false; this._glow.mouseChildren = false; this._glow.alpha = GLOW_BASE;
         this._crt.addChild(this._glow);
         var gg:Graphics = this._glow.graphics;
         var gm:Matrix = new Matrix(); gm.createGradientBox(fw * 1.2, fh * 1.2, 0, fx - fw * 0.1, fy - fh * 0.1);
         gg.beginGradientFill(GradientType.RADIAL, [Theme.PHOS, Theme.PHOS], [0.06, 0.0], [0, 180], gm);
         gg.drawRect(fx, fy, fw, fh); gg.endFill();

         // FEATURE A (0.0.37) SCAN SWEEP: a soft bright horizontal band (mockup #scanroll::after). Drawn ONCE at
         // local origin (top at y=0) as a vertical transparent->phosphor->transparent gradient; onTick travels it
         // top->bottom via .y and eases .alpha at both ends. Pooled Sprite, graphics-only, mouse-transparent.
         this._sweep = new Sprite(); this._sweep.mouseEnabled = false; this._sweep.mouseChildren = false; this._sweep.alpha = 0;
         this._crt.addChild(this._sweep);
         var wg:Graphics = this._sweep.graphics;
         var wm:Matrix = new Matrix(); wm.createGradientBox(fw, SWEEP_H, 90 * Math.PI / 180, fx, 0);
         wg.beginGradientFill(GradientType.LINEAR, [Theme.PHOS, Theme.PHOS, Theme.PHOS], [0.0, 0.055, 0.0], [0, 128, 255], wm);
         wg.drawRect(fx, 0, fw, SWEEP_H); wg.endFill();
         this._sweep.y = fy - SWEEP_H;   // start fully above the frame (no text set here -> geometry-before-text N/A)

         // rolling scanlines: fine phosphor hairlines (1px on / 2px off), drawn once, animated by .y (roll) +
         // .alpha (ease-in on open). Filled 1px rects (render reliably) instead of hairline strokes.
         this._scan = new Sprite(); this._scan.mouseEnabled = false; this._scan.mouseChildren = false; this._scan.alpha = 0;
         this._crt.addChild(this._scan);
         var sg:Graphics = this._scan.graphics;
         sg.beginFill(Theme.PHOS, 0.06);
         for (var yy:Number = fy - 3; yy <= fy + fh + 3; yy += 3) { sg.drawRect(fx, yy, fw, 1); }
         sg.endFill();
      }

      // One vignette edge band. dir: 90=fade down, 270=fade up, 0=fade right, 180=fade left. a = max alpha.
      private function vignetteBand(g:Graphics, x:Number, y:Number, w:Number, h:Number, dir:Number, a:Number = 0.2):void
      {
         var m:Matrix = new Matrix(); m.createGradientBox(w, h, dir * Math.PI / 180, x, y);
         g.beginGradientFill(GradientType.LINEAR, [0x000000, 0x000000], [a, 0.0], [0, 255], m);
         g.drawRect(x, y, w, h); g.endFill();
      }

      // Build the CRT power-on layer (topmost, mouse-transparent). Two full-half black shutters meet at the vertical
      // center (covering the whole picture), plus a phosphor bloom and a bright seam line. onAdded arms it and onTick
      // retracts the shutters (scaleY 1->0) to reveal the picture as an opening slit. Graphics drawn ONCE here; the
      // animation is Sprite scaleY/.alpha/.visible only -> no TextField geometry, crash law holds.
      private function buildPower():void
      {
         var fx:Number = FRAME_X, fy:Number = FRAME_Y, fw:Number = FRAME_W, fh:Number = FRAME_H;
         var cy:Number = fy + fh / 2;
         this._power = new Sprite(); this._power.mouseEnabled = false; this._power.mouseChildren = false; addChild(this._power);
         // top shutter: origin at fy, black rect drawn DOWNWARD over the top half -> scaleY 1->0 retracts UP to fy.
         this._shTop = new Sprite(); this._shTop.mouseEnabled = false; this._shTop.mouseChildren = false; this._shTop.y = fy;
         this._shTop.graphics.beginFill(0x000000, 1); this._shTop.graphics.drawRect(fx, 0, fw, fh / 2); this._shTop.graphics.endFill();
         this._power.addChild(this._shTop);
         // bottom shutter: origin at fy+fh, black rect drawn UPWARD over the bottom half -> scaleY 1->0 retracts DOWN.
         this._shBot = new Sprite(); this._shBot.mouseEnabled = false; this._shBot.mouseChildren = false; this._shBot.y = fy + fh;
         this._shBot.graphics.beginFill(0x000000, 1); this._shBot.graphics.drawRect(fx, -fh / 2, fw, fh / 2); this._shBot.graphics.endFill();
         this._power.addChild(this._shBot);
         // phosphor bloom (full frame), fill at full; controlled by .alpha so it can settle after the reveal.
         this._flash = new Sprite(); this._flash.mouseEnabled = false; this._flash.mouseChildren = false; this._flash.alpha = 0;
         this._flash.graphics.beginFill(Theme.PHOS, 1); this._flash.graphics.drawRect(fx, fy, fw, fh); this._flash.graphics.endFill();
         this._power.addChild(this._flash);
         // bright center seam marking the opening slit; brightest when closed, fades as the shutters part.
         this._seam = new Sprite(); this._seam.mouseEnabled = false; this._seam.mouseChildren = false; this._seam.alpha = 0;
         this._seam.graphics.beginFill(Theme.PHOS_BRIGHT, 1); this._seam.graphics.drawRect(fx, cy - 2, fw, 4); this._seam.graphics.endFill();
         this._power.addChild(this._seam);
      }

      // Redraw the tab boxes/icons/accents + label colors for the active page. GRAPHICS + textColor ONLY: no
      // field creation, no .width. Cheap; only called when the page changes (and once at build).
      private function paintTabs(cp:int):void
      {
         var g:Graphics = this._tabBar.graphics;
         g.clear();
         var i:int, ty:Number, active:Boolean;
         for (i = 0; i < this._tabLabels.length; i++) {
            ty = Number(this._tabY[i]); active = (i == cp);
            var hov:Boolean = (i == this._hoverIdx);   // P1-B: hovered-but-inactive highlight
            if (active) {
               g.beginFill(Theme.SEL, 0.18); g.drawRoundRect(this.BX, ty, this.BW, this.TABH, 8, 8); g.endFill();
               g.lineStyle(1, Theme.PHOS, 0.9); g.drawRoundRect(this.BX, ty, this.BW, this.TABH, 8, 8); g.lineStyle();
               g.beginFill(Theme.SEL, 1); g.drawRoundRect(this.BX - 1, ty + 6, 3, this.TABH - 12, 2, 2); g.endFill();
            } else {
               if (hov) { g.beginFill(Theme.SEL, 0.07); g.drawRoundRect(this.BX, ty, this.BW, this.TABH, 8, 8); g.endFill(); }
               g.lineStyle(1, hov ? Theme.PHOS : Theme.LINE, hov ? 0.6 : 0.22); g.drawRoundRect(this.BX, ty, this.BW, this.TABH, 8, 8); g.lineStyle();
            }
            this.drawIcon(g, i, this.BX + 22, ty + this.TABH / 2, active || hov);
            (this._tabLabels[i] as TextField).textColor = active ? Theme.PHOS_BRIGHT : (hov ? Theme.PHOS : Theme.PHOS_DIM);
         }
         for (i = 0; i < this._extLabels.length; i++) {
            ty = Number(this._extY[i]); active = (cp == (5 + i));
            var ehov:Boolean = (this._hoverIdx == (5 + i));   // P1-B
            if (active) {
               g.beginFill(Theme.SEL, 0.14); g.drawRoundRect(this.BX, ty, this.BW, this.EXTH, 6, 6); g.endFill();
               g.lineStyle(1, Theme.SEL, 0.8); g.drawRoundRect(this.BX, ty, this.BW, this.EXTH, 6, 6); g.lineStyle();
               g.beginFill(Theme.SEL, 1); g.drawRect(this.BX - 1, ty + 4, 3, this.EXTH - 8); g.endFill();
            } else {
               if (ehov) { g.beginFill(Theme.SEL, 0.06); g.drawRoundRect(this.BX, ty, this.BW, this.EXTH, 6, 6); g.endFill(); }
               g.lineStyle(1, ehov ? Theme.PHOS : Theme.LINE, ehov ? 0.5 : 0.14); g.drawRoundRect(this.BX, ty, this.BW, this.EXTH, 6, 6); g.lineStyle();
            }
            Theme.diamond(g, this.BX + 11, ty + this.EXTH / 2, 3, (active || ehov) ? Theme.PHOS_BRIGHT : Theme.PHOS_FAINT);
            (this._extLabels[i] as TextField).textColor = active ? Theme.PHOS_BRIGHT : (ehov ? Theme.PHOS : Theme.PHOS_DIM);
         }
      }

      // P1-B: hover paint. A hovered-but-inactive tab brightens its border + label (mockup .tabbtn:hover);
      // the active state always wins in paintTabs, so hover never fights it. Graphics + textColor ONLY (no
      // field creation, no geometry-after-text, no .width) -> ctor_text_check gates stay green.
      private function onTabOver(e:MouseEvent):void
      {
         var nm:String = String(e.currentTarget.name); var idx:int = -99;
         if (nm.substr(0, 2) == "pt") { idx = int(nm.substr(2)); }
         else if (nm.substr(0, 2) == "ex") { idx = 5 + int(nm.substr(2)); }
         if (idx == this._hoverIdx) { return; }
         this._hoverIdx = idx; this.paintTabs(this._lastPage);
      }
      private function onTabOut(e:MouseEvent):void
      {
         if (this._hoverIdx == -99) { return; }
         this._hoverIdx = -99; this.paintTabs(this._lastPage);
      }

      // Per-page vector glyph (font-independent line-art). cx/cy = icon center.
      private function drawIcon(g:Graphics, page:int, cx:Number, cy:Number, active:Boolean):void
      {
         var c:uint = active ? Theme.PHOS_BRIGHT : Theme.PHOS_DIM;
         g.lineStyle(1.6, c, 1);
         switch (page) {
            case 0:  // STAT - pulse / heartbeat
               g.moveTo(cx - 9, cy); g.lineTo(cx - 3, cy); g.lineTo(cx - 1, cy - 7); g.lineTo(cx + 2, cy + 7); g.lineTo(cx + 4, cy); g.lineTo(cx + 9, cy);
               break;
            case 1:  // INV - lock
               g.drawRoundRect(cx - 6, cy - 1, 12, 9, 2, 2);
               g.moveTo(cx - 3, cy - 1); g.lineTo(cx - 3, cy - 4); g.curveTo(cx, cy - 9, cx + 3, cy - 4); g.lineTo(cx + 3, cy - 1);
               break;
            case 2:  // DATA - document
               g.drawRect(cx - 6, cy - 8, 12, 16);
               g.moveTo(cx - 2, cy - 3); g.lineTo(cx + 3, cy - 3);
               g.moveTo(cx - 2, cy);     g.lineTo(cx + 3, cy);
               g.moveTo(cx - 2, cy + 3); g.lineTo(cx + 3, cy + 3);
               break;
            case 3:  // MAP - pin
               g.drawCircle(cx, cy - 2, 5);
               g.moveTo(cx - 4, cy + 1); g.lineTo(cx, cy + 8); g.lineTo(cx + 4, cy + 1);
               break;
            default: // RADIO - antenna
               g.moveTo(cx, cy + 8); g.lineTo(cx, cy - 4);
               g.moveTo(cx - 5, cy + 2); g.curveTo(cx, cy - 7, cx + 5, cy + 2);
               g.moveTo(cx - 8, cy + 4); g.curveTo(cx, cy - 12, cx + 8, cy + 4);
               break;
         }
         g.lineStyle();
      }

      // 0.0.50 PIPBOYTABS COMPAT: the EXTENSIONS entries are NOT separate pages. PipboyTabs injects them as extra
      // SUB-TABS of existing pages (its ini PageNumberToInsert: 0=STAT page, 2=DATA page; decompiled PipboyTabs.as
      // pushes tab names onto the host page's _TabNames). The old TryToSetPage(5/6/7) targeted pages that DO NOT
      // EXIST (a menu-state wedge risk). Now each ext button routes to its HOST PAGE (CHALLENGES/AFFINITY -> DATA,
      // MAGAZINES -> STAT); the page's own sub-tab strip (0.0.50 PBT-aware) then shows the injected tab to click.
      private static const EXT_HOST_PAGE:Array = [2, 2, 0];   // CHALLENGES, AFFINITY, MAGAZINES -> host page index
      private function onTabHit(e:MouseEvent):void
      {
         var nm:String = String(e.currentTarget.name);
         var idx:int = -1;
         if (nm.substr(0, 2) == "pt") { idx = int(nm.substr(2)); }
         else if (nm.substr(0, 2) == "ex") {
            var ei:int = int(nm.substr(2));
            idx = (ei >= 0 && ei < EXT_HOST_PAGE.length) ? int(EXT_HOST_PAGE[ei]) : -1;
         }
         if (idx < 0) { return; }
         if (this._dbg != null) { this._dbg.input("tab", idx, e.currentTarget); }
         try {
            if (this._menu != null) { this._menu.TryToSetPage(idx); if (this._dbg != null) { this._dbg.mark("setPage" + idx); } }
         } catch (er:*) {}
      }

      // Time-based poll (Ticker is getTimer/clamped; HUD is 30fps). Update text/color + redraw graphics ONLY -
      // never create a field, never set .width. Also drives the CRT scanline roll + ease-in.
      private function onTick(dt:Number):void
      {
         this.PipOS_life = Theme.LIFE;   // 0.0.52 forensics mirror (string assign only; DLL reads + logs it)
         // CRT scanlines: ease alpha 0 -> ~0.55 over the first ~3s, then hold; roll continuously (0..3 px).
         if (this._scan != null) {
            this._crtT += dt;
            var a:Number = this._crtT / 3.0; if (a > 1) { a = 1; }
            this._scan.alpha = 0.55 * a;
            this._roll = (this._roll + dt * 9.0) % 3.0;   // ~9 px/s downward roll
            this._scan.y = this._roll;

            // FEATURE A BREATHE: slow sinusoidal oscillation on the phosphor glow's Sprite.alpha (time-based off
            // _crtT so it honours the 30fps root). Sprite.alpha ONLY -> no redraw, no TextField, no geometry.
            if (this._breathe && this._glow != null) {
               this._glow.alpha = GLOW_BASE + GLOW_AMP * Math.sin(this._crtT * (2 * Math.PI / BREATHE_PERIOD));
            } else if (!this._breathe && this._glow != null) {
               this._glow.alpha = GLOW_BASE;   // breathing off: hold the glow at its base alpha (no oscillation)
            }
            // FEATURE A SCAN SWEEP: travel the soft band top->bottom every SWEEP_PERIOD, alpha-eased at both ends
            // (mockup scansweep 12%..88% plateau). Sprite .y + .alpha ONLY (the band is a non-text layer, so this
            // .y write is not a geometry-after-text vector).
            if (CRT_SWEEP && this._sweep != null) {
               this._sweepT += dt; if (this._sweepT >= SWEEP_PERIOD) { this._sweepT -= SWEEP_PERIOD; }
               var sp:Number = this._sweepT / SWEEP_PERIOD;                      // 0..1
               this._sweep.y = (FRAME_Y - SWEEP_H) + sp * (FRAME_H + SWEEP_H);   // above-frame -> below-frame
               var sa:Number = 1;
               if (sp < 0.12) { sa = sp / 0.12; } else if (sp > 0.88) { sa = (1 - sp) / 0.12; }
               this._sweep.alpha = sa;
            }
         }
         // 0.0.44 CRT POWER-ON: retract the two shutters from center (scaleY 1->0) to reveal the picture as an
         // opening slit, then settle a phosphor bloom. Sprite scaleY/.alpha/.visible ONLY (container transforms) --
         // no geometry, no TextField. Time-based off dt (30fps root). Self-disarms when the bloom finishes.
         if (this._powerOn) {
            this._powerT += dt * this._openSpeed;   // 0.0.60: user speed multiplier (slider); 1.0 = shipped timing
            var pt:Number = this._powerT;
            if (pt < POWER_REVEAL) {
               var rp:Number = pt / POWER_REVEAL;
               var re:Number = rp * rp * (3 - 2 * rp);   // smoothstep 0->1
               var sc:Number = 1 - re; if (sc < 0) { sc = 0; }
               if (this._shTop != null) { this._shTop.scaleY = sc; }
               if (this._shBot != null) { this._shBot.scaleY = sc; }
               if (this._seam != null)  { this._seam.alpha = 0.9 * (1 - re); }   // brightest closed, fades open
               if (this._flash != null) { this._flash.alpha = 0.18 * re; }       // bloom builds as the picture arrives
            } else {
               if (this._shTop != null) { this._shTop.visible = false; }
               if (this._shBot != null) { this._shBot.visible = false; }
               if (this._seam != null)  { this._seam.alpha = 0; }
               var fp:Number = (pt - POWER_REVEAL) / POWER_FLASH; if (fp > 1) { fp = 1; }
               if (this._flash != null) { this._flash.alpha = 0.18 * (1 - fp); }   // settle to nothing
               if (fp >= 1) { if (this._flash != null) { this._flash.visible = false; } this._powerOn = false; }
            }
         }
         // 0.0.56 SHELL MEDIC. Forensics (0.0.52-0.0.55, life-trail + MENUKIDS + shell decomp) proved the wedge:
         // for the STATS slot the page SWF loads and `content as PipboyPage` casts fine, but the vanilla shell's
         // onPageLoadComplete dies before addChild -> page orphaned off-stage, private _IsLoadingPage stuck true,
         // InvalidatePartialData no-ops forever -> menu-wide event death (blank page, dead navigation, PipboyTabs
         // overlays frozen default-visible + focus-grab). PipboyTabs was exonerated (wedge identical with it
         // disabled). The chrome runs before/through the wedge, and every repair step is PUBLIC on the shell:
         // detect the exact signature (CurrentPage object exists but is NOT staged) and finish the shell's job.
         try {
            if (this._menu != null) {
               var mpage:* = null;
               try { mpage = this._menu.CurrentPage; } catch (em1:*) { mpage = null; }
               if (mpage != null && mpage.stage == null) {
                  try { mpage.InitCodeObj(this._menu.BGSCodeObj); } catch (em2:*) {}
                  try { this._menu.addChild(mpage); } catch (em3:*) {}
                  try { this._menu.ButtonHintBar_mc.SetButtonHintData(mpage.buttonHintDataV); } catch (em4:*) {}
                  // Try to clear the shell's stuck private flag (GFx AS3 is sometimes lax about sealed access).
                  // Success => the shell's own InvalidateData pump works again (page switching heals too).
                  this._medicFlagStuck = true;
                  try { this._menu["_IsLoadingPage"] = false; this._medicFlagStuck = false; Theme.life("MD.flag1"); } catch (em5:*) { Theme.life("MD.flag0"); }
                  try { this._menu.InvalidateData(); } catch (em6:*) {}
                  Theme.life("MD.heal");
                  this._medicRedisp = 0;
                  // 0.0.62 RE-ENTRY FIX: on the FIRST STATUS open the shell's own InvalidateData synchronously
                  // dispatches the data event that fills the page (trail: MD.flag1>ST.e0>MD.heal). On a page
                  // SWITCH BACK to a page, clearing _IsLoadingPage succeeds (MD.flag1) so the substitute pump
                  // below is disabled -- but the shell does NOT re-dispatch, so the freshly-staged page instance
                  // never receives a data event (trail: MD.flag1>MD.heal, no ST.e) and renders EMPTY (missing
                  // STATUS meters / DATA quest log). So ALWAYS dispatch one full-mask event to the just-healed
                  // page here, regardless of the flag-clear result. The page's onPipboyChangeEvent is the normal
                  // idempotent data path, so a duplicate on first open is harmless.
                  try {
                     if (stage != null && mpage.stage != null) {
                        PipboyChangeEvent.DispatchEvent(new PipboyUpdateMask(4294967295), stage, this._menu.DataObj, mpage.TabNames);
                        Theme.life("MD.pump");
                     }
                  } catch (emp:*) {}
               }
               // 0.0.59: REMOVE the vanilla button-hint bar from the display list. Neither alpha=0 (0.0.46+) nor
               // y=4000/visible=false (0.0.58) survived in the field, and the log explains why: the pages update
               // their BSButtonHintData texts every refresh ("STIMPAK (5)"...), each update re-triggers the bar's
               // own redraw/re-show AFTER our per-tick write -- and our own medic pump fires one such refresh
               // every 0.5s. removeChild is immune to redraws (nothing in the shell ever re-addChild's the bar;
               // SetButtonHintData still works on the detached instance, so the medic path is unaffected).
               // Guarded per tick in case anything ever re-parents it. KB.rm in the life trail = it happened.
               try {
                  var vb:* = this._menu.ButtonHintBar_mc;
                  if (vb != null) {
                     if (vb.parent != null) { vb.parent.removeChild(vb); Theme.life("KB.rm"); }
                     vb.visible = false; vb.alpha = 0; vb.mouseEnabled = false; vb.mouseChildren = false;
                  }
               } catch (em8:*) {}
               // 0.0.62: the faint STIMPAK/VAULT BOY/LEVEL-UP prompts still visible behind our keybar are the
               // SEPARATE Pipboy_BottomBar (Menu_mc child [0]), which stage1b only DIMMED, not hid -- it carries
               // the engine's own hint line. Fully hide it per tick (our chrome draws its own clock + frame, so
               // nothing we need lives here). visible=false is a display flag the shell's data redraw won't reset.
               try {
                  var bb:* = this._menu.BottomBar_mc;
                  if (bb != null) { bb.visible = false; bb.mouseEnabled = false; bb.mouseChildren = false; }
               } catch (em8b:*) {}
               // If the flag stayed stuck, the shell can't pump events; substitute a full-mask re-dispatch every
               // 0.5s -- and IMMEDIATELY when the native page/tab changes (0.0.57: makes sub-tab clicks feel
               // instant instead of waiting for the next 0.5s beat).
               if (this._medicFlagStuck && stage != null) {
                  var pumpNow:Boolean = false;
                  try {
                     var dd:* = this._menu.DataObj;
                     if (dd != null) {
                        var np:int = int(dd.CurrentPage); var nt:int = int(dd.CurrentTab);
                        if (np != this._pumpLastPage || nt != this._pumpLastTab) { this._pumpLastPage = np; this._pumpLastTab = nt; pumpNow = true; }
                     }
                  } catch (em9:*) {}
                  this._medicRedisp += dt;
                  if (pumpNow || this._medicRedisp >= 0.5) {
                     this._medicRedisp = 0;
                     try {
                        var mp2:* = this._menu.CurrentPage;
                        if (mp2 != null && mp2.stage != null) {
                           PipboyChangeEvent.DispatchEvent(new PipboyUpdateMask(4294967295), stage, this._menu.DataObj, mp2.TabNames);
                        }
                     } catch (em7:*) {}
                  }
               }
            }
         } catch (em0:*) {}
         try {
            if (this._menu == null) { return; }
            var d:* = null; var cp:int = -1;
            try { d = this._menu.DataObj; if (d != null) { cp = int(d.CurrentPage); } } catch (e2:*) {}
            if (cp != this._lastPage) {
               this._lastPage = cp;
               this.paintTabs(cp);
               if (this._dbg != null) { this._dbg.pageTab(cp, "-"); }
            }
            if (d != null) {
               try {
                  Theme.setText(this._clockDate, this.pad(d.DateMonth) + "." + this.pad(d.DateDay) + "." + d.DateYear);
                  var h:int = int(d.TimeHour); var mnt:int = int((Number(d.TimeHour) - h) * 60);
                  Theme.setText(this._clockTime, this.pad(h) + ":" + this.pad(mnt));
               } catch (e3:*) {}
            }
         } catch (er:*) {}
      }
      private function pad(v:*):String { var s:String = String(int(v)); return (s.length < 2) ? ("0" + s) : s; }

      // Compatibility no-ops (a byte-identical vanilla shell never calls these; harmless if a variant does).
      public function updateData(data:Object, menu:Object):void { try { if (menu != null) { this._menu = menu; } } catch (er:*) {} }
      public function playCollapse():void {}
      public function playBoot():void {}
   }
}
