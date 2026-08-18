package
{
   import Shared.AS3.BSUIComponent;

   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   public class PipboySubMenu extends BSUIComponent
   {
      public static const READ_ONLY_NONE:int = 0;
      public static const READ_ONLY_DEFAULT:int = 1;
      public static const READ_ONLY_OFFLINE:int = 2;
      public static const READ_ONLY_DEMO:int = 3;
      protected var BGSCodeObj:Object;
      protected var _ReadOnlyMode:Boolean;
      public var _ReadOnlyModeType:int;
      public function PipboySubMenu() { super(); }
      public function InitCodeObj(param1:Object):* { this.BGSCodeObj = param1; }
      public function ReleaseCodeObj():* { this.BGSCodeObj = null; }
      public function get codeObj():Object { return this.BGSCodeObj; }
      protected function onPipboyChangeEvent(param1:PipboyChangeEvent):void {}
      protected function onReadOnlyChanged(param1:Boolean):void {}
      public function ProcessUserEvent(param1:String, param2:Boolean):Boolean { return false; }
      public function GetIsUsingRightStick():Boolean { return false; }
      public function onRightThumbstickInput(param1:uint):* {}
      protected function GetUpdateMask():PipboyUpdateMask { return PipboyUpdateMask.None; }
   }
}
