#pragma once

#include "RE/B/BSFixedString.h"
#include "RE/N/NiExtraData.h"
#include "RE/N/NiNode.h"

namespace RE
{
    struct BSFaceGenExpression
    {
        float expression[54];
    };
    static_assert(sizeof(BSFaceGenExpression) == 0xD8);

    class BSFaceGenAnimationData : public NiExtraData
    {
    public:
        BSFaceGenExpression currentExpression;
        BSFaceGenExpression modifierExpression;
        BSFaceGenExpression baseExpression;
        std::array<std::byte, 0x38> emotionalIdleData;
        bool morphsDirty;
        bool forceMorphUpdate;
        std::uint8_t pad2DA;
        bool disableMorphUpdate;
        std::uint32_t morphUpdateState;
        std::uint32_t unk2E0;
        std::uint32_t pad2E4;
    };
    static_assert(sizeof(BSFaceGenAnimationData) == 0x2E8);

    class BSFaceGenNiNode : public NiNode
    {
    public:
        std::array<std::byte, 0x30> faceGenData;
        BSFaceGenAnimationData* animationData;
        float updateTime;
        std::uint16_t faceGenFlags;
    };
    static_assert(offsetof(BSFaceGenNiNode, animationData) == 0x170);
    static_assert(offsetof(BSFaceGenNiNode, faceGenFlags) == 0x17C);
}
