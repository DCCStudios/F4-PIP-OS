package pipos
{
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.geom.Rectangle;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;

   // PIP-OS reimplementation of the vanilla Shared.AS3.ConditionBoy composite (see
   // docs/ScaleformContract.md Section e). Loads the game's own condition clips at runtime and
   // composites head into body per the decompiled placement, then tints toward phosphor.
   // This is the shipping STAT figure fallback (no Meshy art, no DLL required).
   public class VaultBoy extends Sprite
   {
      private var _body:MovieClip;
      private var _head:MovieClip;
      private var _bodyFlags:int = -1;
      private var _headFlags:int = 0;
      private var _bodyLoader:Loader;
      private var _headLoader:Loader;
      private var _fitH:Number = 360;   // target height inside the STAT figure panel
      private var _content:Sprite;      // holds body; we normalize/scale/center this

      public function VaultBoy(fitHeight:Number = 360)
      {
         super();
         this._fitH = fitHeight;
         this._content = new Sprite();
         addChild(this._content);
         // 0.0.49/0.0.50: the head ConditionClips Loader.load() is DEFERRED out of the ctor (the page ctor runs
         // during the shell's ProcessLoadQueue construction; external loads belong on-stage -- vanilla ConditionBoy
         // timing). 0.0.50: VaultBoy now SELF-ARMS on ADDED_TO_STAGE, so every host page (Inv figure slot, Stats
         // figure) gets the head load without remembering to call begin() -- 0.0.49 only wired StatsPage and the
         // Inventory Vault Boy vanished. begin() stays public + idempotent for explicit callers.
         addEventListener(Event.ADDED_TO_STAGE, this.onVbStage);
      }
      private function onVbStage(e:Event):void { removeEventListener(Event.ADDED_TO_STAGE, this.onVbStage); this.begin(); }

      // Start the head ConditionClips load. MUST be called ON-STAGE (post page install), never from the ctor.
      public function begin():void
      {
         if (this._headLoader != null) { return; }   // once
         try {
            this._headLoader = new Loader();
            this._headLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onHead);
            this._headLoader.contentLoaderInfo.addEventListener(flash.events.IOErrorEvent.IO_ERROR, this.onLoadErr);
            this._headLoader.load(new URLRequest("Components/ConditionClips/Condition_Head.swf"),
                                  new LoaderContext(false, ApplicationDomain.currentDomain));
         } catch (e:Error) {}
      }

      public function setFlags(bodyFlags:uint, headFlags:uint):void
      {
         this._headFlags = headFlags;
         if (this._bodyFlags != int(bodyFlags))
         {
            this._bodyFlags = int(bodyFlags);
            if (this._bodyLoader) { try { this._bodyLoader.unloadAndStop(); } catch (e:Error) {} }
            this._bodyLoader = new Loader();
            this._bodyLoader.contentLoaderInfo.addEventListener(Event.COMPLETE, this.onBody);
            this._bodyLoader.contentLoaderInfo.addEventListener(flash.events.IOErrorEvent.IO_ERROR, this.onLoadErr);
            try {
               this._bodyLoader.load(new URLRequest("Components/ConditionClips/Condition_Body_" + this._bodyFlags + ".swf"),
                                     new LoaderContext(false, ApplicationDomain.currentDomain));
            } catch (e2:Error) {}
         }
         else { this.composite(); }
      }

      private function onLoadErr(e:flash.events.IOErrorEvent):void { }   // G7: ConditionClips missing under MO2/BA2 must NOT throw

      private function onHead(e:Event):void
      {
         this._head = this._headLoader.content as MovieClip;
         this.composite();
      }
      private function onBody(e:Event):void
      {
         this._body = this._bodyLoader.content as MovieClip;
         this.composite();
      }

      private function composite():void
      {
         if (this._body == null || this._head == null) { return; }
         while (this._content.numChildren > 0) { this._content.removeChildAt(0); }
         try
         {
            // Composite head into the body's Head_mc slot per the decompiled ConditionBoy.as.
            if (this._body.Head_mc != null) { this._body.Head_mc.addChild(this._head); }
            this._head.gotoAndStop(this._headFlags + 1);
            this._body.scaleX = 1.0; this._body.scaleY = 1.0;
            this._content.addChild(this._body);

            // The condition art sits off-stage at authoring coords (JPEXS gotcha), so the raw content
            // has arbitrary bounds. Normalize to (0,0), scale to fit the panel height, then center
            // the content horizontally about local x=0 and top-align at local y=0 so the STAT page can
            // place it by the panel's top-center without the figure spilling above the panel.
            var b:Rectangle = this._content.getBounds(this._content);
            if (b.height > 1)
            {
               var s:Number = this._fitH / b.height;
               if (s > 2.2) { s = 2.2; }
               this._content.scaleX = s; this._content.scaleY = s;
               var b2:Rectangle = this.getBounds(this);   // bounds after scale, in VaultBoy space
               this._content.x -= (b2.x + b2.width / 2);   // center horizontally about x=0
               this._content.y -= b2.y;                    // top at y=0
            }

            // phosphor tint
            var ct:* = this.transform.colorTransform;
            ct.redMultiplier = 0.53; ct.greenMultiplier = 0.88; ct.blueMultiplier = 0.55;
            this.transform.colorTransform = ct;
         }
         catch (err:Error) {}
      }
   }
}
