package pipos
{
   import flash.display.DisplayObject;
   import flash.events.Event;
   import flash.utils.getTimer;

   // Time-based animation driver. Loaded child SWFs run at the ROOT movie's frame cadence (30 fps for
   // the Pip-Boy), so animations MUST advance by measured elapsed time, not a hardcoded per-tick delta.
   // Delta is clamped to [1/240, 1/12] s (S2 HUD Rework's proven clamp) to survive pauses/hitches/alt-tab.
   public class Ticker
   {
      public static const MIN_DT:Number = 1 / 240;
      public static const MAX_DT:Number = 1 / 12;

      private var _last:int = -1;
      private var _host:DisplayObject;
      private var _cb:Function;   // function(dt:Number):void

      public function Ticker(host:DisplayObject, callback:Function)
      {
         this._host = host;
         this._cb = callback;
      }

      public function start():void
      {
         this._last = getTimer();
         this._host.addEventListener(Event.ENTER_FRAME, this.onFrame);
      }
      public function stop():void
      {
         this._host.removeEventListener(Event.ENTER_FRAME, this.onFrame);
      }

      private function onFrame(e:Event):void
      {
         var now:int = getTimer();
         var dt:Number = (now - this._last) / 1000;
         this._last = now;
         if (dt < MIN_DT) { dt = MIN_DT; }
         if (dt > MAX_DT) { dt = MAX_DT; }
         if (this._cb != null) { this._cb(dt); }
      }
   }
}
