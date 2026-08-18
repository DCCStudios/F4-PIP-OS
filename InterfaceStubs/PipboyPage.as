package
{
   import Shared.AS3.BSButtonHintData;

   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   public class PipboyPage extends PipboySubMenu
   {
      public static const LOWER_PIPBOY_ALLOW_CHANGE:String = "PipboyPage::LowerPipboyAllowedChange";
      public static const BOTTOM_BAR_UPDATE:String = "PipboyPage::BottomBarUpdate";
      protected var _TabNames:Array;
      protected var _buttonHintDataV:Vector.<BSButtonHintData>;
      public function PipboyPage()
      {
         super();
         this._buttonHintDataV = new Vector.<BSButtonHintData>();
         this.PopulateButtonHintData();
      }
      public function get TabNames():Array { return this._TabNames; }
      public function get buttonHintDataV():Vector.<BSButtonHintData> { return this._buttonHintDataV; }
      protected function PopulateButtonHintData():* {}
      public function CanSwitchFromCurrentPage():Boolean { return true; }
      public function CanSwitchTabs(param1:uint):Boolean { return this._TabNames != null && param1 < this._TabNames.length; }
      public function CanLowerPipboy():Boolean { return true; }
      protected function HandleMobileBackButton():Boolean { return false; }
   }
}
