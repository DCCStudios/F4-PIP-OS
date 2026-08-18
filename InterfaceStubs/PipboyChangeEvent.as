package
{
   import flash.display.Stage;
   import flash.events.Event;

   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   public class PipboyChangeEvent extends Event
   {
      public static const CHANGE:String = "PipboyChangeEvent::Change";
      public function PipboyChangeEvent(type:String) { super(type, true, true); }
      public function get DataObj():Pipboy_DataObj { return null; }
      public function get UpdateMask():PipboyUpdateMask { return null; }
      public function get TabNames():Array { return null; }
      public static function Register(param1:Stage, param2:Function):void {}
      public static function Unregister(param1:Stage, param2:Function):void {}
      public static function DispatchEvent(param1:*, param2:Stage, param3:Pipboy_DataObj, param4:Array):void {}
   }
}
