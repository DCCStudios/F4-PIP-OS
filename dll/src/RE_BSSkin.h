#pragma once

#include "RE/B/BSTArray.h"
#include "RE/N/NiBound.h"
#include "RE/N/NiObject.h"
#include "RE/N/NiPointer.h"
#include "RE/N/NiTransform.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace RE::BSSkin
{
	inline constexpr std::uint32_t kMaxExpectedBones = 1024;

	class BoneData :
		public NiObject
	{
	public:
		struct BoneTransforms
		{
			NiBound     bound;      // 00
			NiTransform transform;  // 10
		};
		static_assert(sizeof(BoneTransforms) == 0x50);

		BSTAlignedArray<BoneTransforms, 0x10> transforms;  // 10
	};
	static_assert(sizeof(BoneData) == 0x28);

	class Instance :
		public NiObject
	{
	public:
		BSTArray<NiAVObject*>  bones;            // 10
		BSTArray<NiTransform*> worldTransforms;  // 28
		NiPointer<BoneData>    boneData;         // 40
		NiAVObject*            rootNode;         // 48
		std::array<std::byte, 0x50> pad50;        // 50
		void*                  currentPalette;   // A0
		void*                  previousPalette;  // A8
		std::uint32_t          paletteCount;     // B0
		std::uint32_t          paletteFlags;     // B4
		std::uint32_t          paletteByteSize;  // B8
		std::uint32_t          paletteStamp;     // BC
	};
	static_assert(sizeof(Instance) == 0xC0);
	static_assert(offsetof(Instance, bones) == 0x10);
	static_assert(offsetof(Instance, worldTransforms) == 0x28);
	static_assert(offsetof(Instance, boneData) == 0x40);
	static_assert(offsetof(Instance, rootNode) == 0x48);
	static_assert(offsetof(Instance, paletteStamp) == 0xBC);
}
