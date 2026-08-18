package
{
   import flash.geom.Point;

   // Compile-only contract; runtime supplied by the shell. External SWC, do not embed.
   // Getter surface mirrors the vanilla Pipboy_DataObj so pages can read live state.
   public class Pipboy_DataObj
   {
      public static const NUM_PAGES:uint = 5;
      public static const NUM_SPECIAL:uint = 7;
      public function Pipboy_DataObj() { super(); }
      public function get CurrentPage():uint { return 0; }
      public function get CurrentTab():uint { return 0; }
      public function get PlayerName():String { return ""; }
      public function get ActiveEffects():Array { return null; }
      public function get StimpakCount():uint { return 0; }
      public function get RadawayCount():uint { return 0; }
      public function get CurrHP():Number { return 0; }
      public function get MaxHP():Number { return 0; }
      public function get CurrAP():Number { return 0; }
      public function get MaxAP():Number { return 0; }
      public function get CurrWeight():Number { return 0; }
      public function get MaxWeight():Number { return 0; }
      public function get CurrentHPGain():Number { return 0; }
      public function get SelectedItemHPGain():Number { return 0; }
      public function get TotalDamages():Array { return null; }
      public function get TotalResists():Array { return null; }
      public function get SlotResists():Array { return null; }
      public function get UnderwearType():uint { return 0; }
      public function get Caps():uint { return 0; }
      public function get DateMonth():uint { return 0; }
      public function get DateDay():uint { return 0; }
      public function get DateYear():uint { return 0; }
      public function get TimeHour():Number { return 0; }
      public function get CurrLocationName():String { return ""; }
      public function get XPLevel():uint { return 0; }
      public function get XPProgressPct():Number { return 0; }
      public function get InvItems():Array { return null; }
      public function get InvComponents():Array { return null; }
      public function get InvFilter():int { return 0; }
      public function get InvSelectedItems():Array { return null; }
      public function get HolotapePlaying():Boolean { return false; }
      public function get SortMode():uint { return 0; }
      public function get FavoritesList():Array { return null; }
      public function get HeadCondition():Number { return 0; }
      public function get TorsoCondition():Number { return 0; }
      public function get LArmCondition():Number { return 0; }
      public function get RArmCondition():Number { return 0; }
      public function get LLegCondition():Number { return 0; }
      public function get RLegCondition():Number { return 0; }
      public function get BodyFlags():uint { return 0; }
      public function get HeadFlags():uint { return 0; }
      public function get SPECIALList():Array { return null; }
      public function get PerksList():Array { return null; }
      public function get PerkPoints():uint { return 0; }
      public function get QuestsList():Array { return null; }
      public function get GeneralStatsList():Array { return null; }
      public function get WorkshopsList():Array { return null; }
      public function get WorldMapMarkers():Array { return null; }
      public function get LocalMapMarkers():Array { return null; }
      public function get WorldMapTextureName():String { return ""; }
      public function get WorldMapNWCorner():Point { return null; }
      public function get WorldMapNECorner():Point { return null; }
      public function get WorldMapSWCorner():Point { return null; }
      public function get LocalMapNWCorner():Point { return null; }
      public function get LocalMapNECorner():Point { return null; }
      public function get LocalMapSWCorner():Point { return null; }
      public function get RadioList():Array { return null; }
      public function get ReadOnlyMode():int { return 0; }
   }
}
