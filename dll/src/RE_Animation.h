#pragma once

// This CommonLibF4 fork forward-declares these two engine types. TF3DHUD's
// private preview graph needs their verified OG layouts to own graphs and
// inspect/filter animation channels without borrowing the live skeleton.

#include "RE/B/BSFixedString.h"
#include "RE/B/BSIntrusiveRefCounted.h"

namespace RE
{
    class BShkbAnimationGraph : public BSIntrusiveRefCounted
    {
    public:
        virtual ~BShkbAnimationGraph() = default;
    };
    static_assert(sizeof(BShkbAnimationGraph) == 0x10);

    class BSAnimationGraphChannel : public BSIntrusiveRefCounted
    {
    public:
        virtual ~BSAnimationGraphChannel() = default;
        virtual void PollChannelUpdate(bool a_shouldApplyAdjustments) = 0;
        virtual void Reset() = 0;

        BSFixedString variableName;  // 10
        std::uint32_t unk18{ 0 };    // 18
    };
    static_assert(offsetof(BSAnimationGraphChannel, variableName) == 0x10);
}
