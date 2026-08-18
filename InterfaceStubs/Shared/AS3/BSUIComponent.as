package Shared.AS3
{
   import flash.display.MovieClip;

   // Compile-only contract. Runtime definition is supplied by PipboyMenu.swf (shell) via the shared
   // ApplicationDomain. Linked as an external SWC; MUST NOT be embedded in the page SWF.
   public dynamic class BSUIComponent extends MovieClip
   {
      public function BSUIComponent() { super(); }
      public function SetIsDirty():void {}
      public function redrawUIComponent():void {}
      public function onAddedToStage():void {}
      public function onRemovedFromStage():void {}
   }
}
