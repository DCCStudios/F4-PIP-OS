package
{
   import Shared.AS3.BSButtonHintData;
   import Shared.BGSExternalInterface;
   import pipos.Theme;
   import flash.display.Sprite;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.text.TextField;

   // PIP-OS Map page. The engine renders the world/local map; this page draws the PIP-OS chrome +
   // marker overlay and drives the vanilla calls (RegisterMap/UnregisterMap, SetPlayerMarker,
   // onSwitchBetweenWorldLocalMap, FastTravel, CenterMarkerRequest). Engine-map rendering into a
   // custom container needs in-game validation; MAP=external (FallUI Map) is the documented fallback.
   public class PipOS_MapPage extends PipboyPage
   {
      private var _title:TextField;
      private var _subtabs:Sprite;
      private var _region:TextField;
      private var _grid:TextField;
      private var _mapName:TextField;
      // (legend is drawn as vectors in drawLegend)
      private var _mapArea:Sprite;   // engine draws here after RegisterMap; also our marker overlay
      private var _markers:Sprite;
      private var _legend:Sprite;
      private var _curTab:int = -1;
      private var _lastData:Pipboy_DataObj;
      private var _registered:Boolean = false;
      private var _panels:Array = [];      // panel rects for the DEBUG clearance overlay

      private const MAP_X:Number = 206;   // right of the sidebar gutter
      private const MAP_Y:Number = 78;    // below the clock card
      private const MAP_W:Number = 652;   // 206..858
      private const MAP_H:Number = 556;   // 78..634 (bottom stays >=10px above the keybar strip)

      private var _local:BSButtonHintData;
      private var _place:BSButtonHintData;

      public function PipOS_MapPage()
      {
         super();
         _TabNames = new Array("$PipboyWorldCategory","$PipboyLocalCategory");
         this.buildChrome();
      }

      override protected function PopulateButtonHintData():*
      {
         this._local = new BSButtonHintData("$LOCAL MAP","R","PSN_X","Xenon_X",1,this.doToggle);
         this._place = new BSButtonHintData("$PLACE MARKER","Enter","PSN_A","Xenon_A",1,this.doPlaceCenter);
         _buttonHintDataV.push(this._local); _buttonHintDataV.push(this._place);
      }

      override protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.Map; }
      private function sfx(ev:String):void { BGSExternalInterface.call(this.codeObj, "PlaySound", ev); }

      override public function onAddedToStage():void
      {
         super.onAddedToStage();
         if (!this._registered) { this._registered = true; BGSExternalInterface.call(this.codeObj, "RegisterMap"); }
      }
      override public function onRemovedFromStage():void
      {
         if (this._registered) { this._registered = false; BGSExternalInterface.call(this.codeObj, "UnregisterMap"); }
         super.onRemovedFromStage();
      }

      private function buildChrome():void
      {
         this._title = Theme.tf(22, Theme.PHOS_BRIGHT, true); this._title.x = Theme.CX; this._title.y = Theme.TITLE_Y; Theme.setText(this._title, "MAP"); addChild(this._title); this._title.visible = false;
         this._subtabs = new Sprite(); this._subtabs.y = Theme.SUB_Y; addChild(this._subtabs);
         var g:* = this.graphics;
         Theme.panelR(g, this._panels, this.MAP_X, this.MAP_Y, this.MAP_W, this.MAP_H, 0.5);
         Theme.brackets(g, this.MAP_X, this.MAP_Y, this.MAP_W, this.MAP_H, 18, Theme.PHOS, 0.7);
         // Mockup map telemetry plates. They remain above the engine map surface and use fixed geometry so
         // location-name refreshes never resize a text-bearing field during an input dispatch.
         g.lineStyle(0, 0, 0); g.beginFill(Theme.PANEL, 0.78);
         g.drawRoundRect(this.MAP_X + 8, this.MAP_Y + 8, 220, 24, 5, 5);
         g.drawRoundRect(this.MAP_X + this.MAP_W - 130, this.MAP_Y + 8, 118, 24, 5, 5);
         g.endFill();
         Theme.frameRect(g, this.MAP_X + 8, this.MAP_Y + 8, 220, 24, Theme.PHOS, 0.42);
         Theme.frameRect(g, this.MAP_X + this.MAP_W - 130, this.MAP_Y + 8, 118, 24, Theme.PHOS, 0.42);
         g.lineStyle(0, 0, 0); g.beginFill(Theme.PANEL, 0.78);
         g.drawRoundRect(Theme.INFO_R - 180, Theme.TITLE_Y, 180, 24, 5, 5);
         g.endFill(); Theme.frameRect(g, Theme.INFO_R - 180, Theme.TITLE_Y, 180, 24, Theme.PHOS, 0.38);

         this._mapArea = new Sprite(); this._mapArea.x = this.MAP_X; this._mapArea.y = this.MAP_Y; addChild(this._mapArea);
         this._mapArea.name = "MapArea_mc";
         this._mapArea.scrollRect = new Rectangle(0, 0, this.MAP_W, this.MAP_H);   // clip markers to the frame
         var hit:Sprite = new Sprite(); hit.graphics.beginFill(0,0); hit.graphics.drawRect(0,0,this.MAP_W,this.MAP_H); hit.graphics.endFill();
         hit.addEventListener(MouseEvent.CLICK, this.onMapClick); this._mapArea.addChild(hit);
         this._markers = new Sprite(); this._mapArea.addChild(this._markers);

         this._region = Theme.tf(12, Theme.PHOS, true, "right"); addChild(this._region);
         this._region.autoSize = "none"; this._region.width = 180; this._region.height = 22;
         this._region.x = Theme.INFO_R - 180; this._region.y = Theme.TITLE_Y + 3; Theme.setText(this._region, "REGION  COMMONWEALTH");
         this._grid = Theme.tf(11, Theme.PHOS_DIM, false); addChild(this._grid);
         this._grid.autoSize = "none"; this._grid.width = 210; this._grid.height = 20;
         this._grid.x = this.MAP_X + 16; this._grid.y = this.MAP_Y + 12; Theme.setText(this._grid, "GRID -");
         this._mapName = Theme.tf(10, Theme.PHOS_BRIGHT, true, "right"); addChild(this._mapName);
         this._mapName.autoSize = "none"; this._mapName.width = 104; this._mapName.height = 18;
         this._mapName.x = this.MAP_X + this.MAP_W - 122; this._mapName.y = this.MAP_Y + 13; Theme.setText(this._mapName, "COMMONWEALTH");
         this.drawLegend();
         addEventListener(KeyboardEvent.KEY_DOWN, this.onKey);
      }

      // Vector legend (glyphs ▲◆●✚ are outside the embedded Basic-Latin range, so draw them).
      private function drawLegend():void
      {
         this._legend = new Sprite(); this._legend.x = this.MAP_X + 10; this._legend.y = this.MAP_Y + this.MAP_H - 36; addChild(this._legend);
         var g:* = this._legend.graphics; var x:Number = 12;
         g.lineStyle(0, 0, 0); g.beginFill(Theme.PANEL, 0.82); g.drawRoundRect(0,0,286,26,5,5); g.endFill(); Theme.frameRect(g, 0, 0, 286, 26, Theme.PHOS, 0.38);
         var items:Array = [["PLAYER", Theme.PHOS_BRIGHT, 4], ["QUEST TARGET", Theme.WARN, 3], ["LOCATION", Theme.PHOS, 3]];
         for each (var it:Array in items)
         {
            g.beginFill(uint(it[1]), 0.9); g.drawCircle(x + 4, 8, Number(it[2])); g.endFill();
            var t:TextField = Theme.tf(10, Theme.PHOS_DIM, false); t.x = x + 12; t.y = 3; Theme.setText(t, String(it[0])); this._legend.addChild(t);
            x += 12 + t.width + 16;
         }
      }

      private function buildSubtabs():void
      {
         while (this._subtabs.numChildren > 0) { this._subtabs.removeChildAt(0); }
         this._subtabs.graphics.clear();
         var names:Array = ["WORLD","LOCAL"]; var x:Number = Theme.CX;
         for (var i:int = 0; i < names.length; i++)
         {
            var on:Boolean = (i == this._curTab);
            var t:TextField = Theme.tf(14, on ? Theme.PHOS_BRIGHT : Theme.PHOS_DIM, on);
            t.name = "s"+i; t.x = x; t.y = 0; Theme.setText(t, names[i]);
            var hit:Sprite = new Sprite(); hit.graphics.beginFill(0,0); hit.graphics.drawRect(x-4,-2,t.width+8,22); hit.graphics.endFill();
            hit.name = "h"+i; hit.buttonMode = true; hit.addEventListener(MouseEvent.MOUSE_DOWN, this.onSubtabClick);
            this._subtabs.addChild(hit); this._subtabs.addChild(t);
            if (on) {
               var cx:Number = x + t.width / 2; this._subtabs.graphics.beginFill(Theme.SEL,0.95);
               this._subtabs.graphics.drawCircle(cx-7,22,1.4); this._subtabs.graphics.drawCircle(cx,22,1.4); this._subtabs.graphics.drawCircle(cx+7,22,1.4);
               this._subtabs.graphics.endFill();
            }
            x += t.width + 26;
         }
      }
      private function onSubtabClick(e:MouseEvent):void { var i:int = int(e.currentTarget.name.substr(1)); if (i != this._curTab) { this.doToggle(); } }

      override protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void
      {
         var d:Pipboy_DataObj = param1.DataObj; this._lastData = d; this._curTab = d.CurrentTab; this.buildSubtabs();
         Theme.setText(this._title, (this._curTab == 1) ? "LOCAL MAP" : "WORLD MAP");
         Theme.setText(this._mapName, (this._curTab == 1) ? "LOCAL" : "COMMONWEALTH");
         if (d.CurrLocationName != null && d.CurrLocationName.length > 0) {
            var location:String = d.CurrLocationName.toUpperCase();
            Theme.setText(this._region, "REGION  " + location);
            Theme.setText(this._grid, "GRID C-4 · " + location);
         } else {
            Theme.setText(this._region, "REGION  COMMONWEALTH");
            Theme.setText(this._grid, "GRID -");
         }
         this.renderMarkers(d);
         SetIsDirty();
      }
      public function debugRects():Array { return this._panels; }

      private function renderMarkers(d:Pipboy_DataObj):void
      {
         while (this._markers.numChildren > 0) { this._markers.removeChildAt(0); }
         this._markers.graphics.clear();
         var arr:Array = (this._curTab == 1) ? d.LocalMapMarkers : d.WorldMapMarkers;
         var nw:Point = (this._curTab == 1) ? d.LocalMapNWCorner : d.WorldMapNWCorner;
         var ne:Point = (this._curTab == 1) ? d.LocalMapNECorner : d.WorldMapNECorner;
         var sw:Point = (this._curTab == 1) ? d.LocalMapSWCorner : d.WorldMapSWCorner;
         if (arr == null) { return; }
         var g:* = this._markers.graphics;
         for (var i:int = 0; i < arr.length && i < 500; i++)   // hard cap: pathological marker sets can't stall the draw
         {
            var m:Object = arr[i]; if (m == null || m.x == null || m.y == null) { continue; }
            var p:Point = this.project(Number(m.x), Number(m.y), nw, ne, sw);
            var col:uint = (m.isQuestTarget == true) ? Theme.WARN : (m.isPlayer == true ? Theme.PHOS_BRIGHT : Theme.PHOS);
            g.beginFill(col, 0.9); g.drawCircle(p.x, p.y, (m.isPlayer == true ? 5 : 3)); g.endFill();
         }
      }

      private function project(wx:Number, wy:Number, nw:Point, ne:Point, sw:Point):Point
      {
         if (nw == null || ne == null || sw == null) { return new Point(this.MAP_W/2, this.MAP_H/2); }
         var uX:Number = (ne.x - nw.x), uY:Number = (ne.y - nw.y);
         var vX:Number = (sw.x - nw.x), vY:Number = (sw.y - nw.y);
         var det:Number = uX * vY - uY * vX; if (det == 0) { return new Point(this.MAP_W/2, this.MAP_H/2); }
         var rx:Number = wx - nw.x, ry:Number = wy - nw.y;
         var a:Number = (rx * vY - ry * vX) / det;   // 0..1 across
         var b:Number = (uX * ry - uY * rx) / det;   // 0..1 down
         return new Point(a * this.MAP_W, b * this.MAP_H);
      }

      private function onMapClick(e:MouseEvent):void
      {
         var lx:Number = this._mapArea.mouseX, ly:Number = this._mapArea.mouseY;
         this.sfx("UIMenuOK");
         BGSExternalInterface.call(this.codeObj, "SetPlayerMarker", lx / this.MAP_W, ly / this.MAP_H);
      }
      private function doPlaceCenter():void { this.sfx("UIMenuOK"); BGSExternalInterface.call(this.codeObj, "SetPlayerMarker", 0.5, 0.5); }
      private function doToggle():void { this.sfx("UIPipBoyMapZoom"); BGSExternalInterface.call(this.codeObj, "onSwitchBetweenWorldLocalMap"); }

      // Map click places a marker (mouse). Keybar actions go through ProcessUserEvent named controls
      // (single path). No list here, so raw KEY_DOWN is unused.
      private function onKey(e:KeyboardEvent):void {}

      override public function ProcessUserEvent(param1:String, param2:Boolean):Boolean
      {
         if (!param2)
         {
            switch (param1)
            {
               case "XButton": this.doToggle();      return true;   // R / Xenon_X (World/Local)
               case "Accept":  this.doPlaceCenter(); return true;   // Enter / Xenon_A (Place marker)
            }
         }
         return false;
      }
   }
}
