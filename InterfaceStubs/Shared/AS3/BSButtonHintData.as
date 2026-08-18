package Shared.AS3
{
   import flash.events.EventDispatcher;

   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   public dynamic class BSButtonHintData extends EventDispatcher
   {
      public function BSButtonHintData(param1:String, param2:String, param3:String, param4:String, param5:uint, param6:Function) { super(); }
      public function get ButtonText():String { return ""; }
      public function set ButtonText(v:String):void {}
      public function get ButtonVisible():Boolean { return true; }
      public function set ButtonVisible(v:Boolean):void {}
      public function get ButtonEnabled():Boolean { return true; }
      public function set ButtonEnabled(v:Boolean):void {}
      public function get ButtonFlashing():Boolean { return false; }
      public function set ButtonFlashing(v:Boolean):void {}
   }
}
