#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

enum class OverlayMode : int
{
    IndirectLighting    = 0,
    Variance            = 1,
    RayCount            = 2,
    RefCount            = 3,
    Life                = 4,
    Coverage            = 5,
};

FALCOR_ENUM_INFO(OverlayMode, {
    { OverlayMode::IndirectLighting, "IndirectLighting" },
    { OverlayMode::Variance, "Variance" },
    { OverlayMode::RayCount, "RayCount" },
    { OverlayMode::RefCount, "RefCount" },
    { OverlayMode::Life, "Life" },
    { OverlayMode::Coverage, "Coverage" },
});
FALCOR_ENUM_REGISTER(OverlayMode);

END_NAMESPACE_FALCOR
