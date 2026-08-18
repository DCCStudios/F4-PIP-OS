package Shared
{
   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   public class BGSExternalInterface
   {
      public function BGSExternalInterface() { super(); }
      public static function call(param1:Object, ... rest):void {}
   }
}
